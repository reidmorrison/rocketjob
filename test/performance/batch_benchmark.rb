#!/usr/bin/env ruby
# frozen_string_literal: true

# In-process Batch performance benchmark / diagnostic harness.
#
# Unlike `bin/rocketjob_batch_perf` (which needs separate `rocketjob` worker
# processes running in other terminals and coordinates over MongoDB), this
# benchmark exercises the batch hot path *inside this one process* so that a
# regression can be attributed to a specific layer.
#
# It is intentionally NOT named `*_test.rb`, so `rake test` (pattern
# `test/**/*_test.rb`) never collects it and CI never runs it. Run it by hand:
#
#   bundle exec ruby -Itest -Ilib test/performance/batch_benchmark.rb
#   MODE=micro   bundle exec ruby -Itest -Ilib test/performance/batch_benchmark.rb
#   MODE=dequeue bundle exec ruby -Itest -Ilib test/performance/batch_benchmark.rb
#
# Modes:
#   throughput  upload COUNT records then process them all in-process (default).
#   micro       break down the per-slice hot path (claim/insert/serialize/parse).
#   dequeue     measure `Worker#find_and_assign_job` contention against ONE
#               running batch job as the worker-thread count rises. This is the
#               scenario that regresses at scale: every worker re-stamps the same
#               running job document via findAndModify on every poll, so MongoDB
#               serializes the writes (WriteConflict retries, server log id 46404)
#               and per-poll latency climbs with the worker count.
#
# Environment variables:
#   COUNT        records to upload/process            (default 1_000_000)
#   SLICE_SIZE   records per slice                    (default 1000)
#   THREADS      worker threads (throughput mode)     (default 1)
#   THREAD_LIST  thread counts to sweep (dequeue)     (default 1,4,8,16)
#   POLLS        polls per thread (dequeue mode)      (default 2000)
#   SERIALIZER   none | compress | encrypt            (default none)
#   OUTPUT       write an output category? true/false (default true)
#   MONGO        mongoid config file                  (default test/config/mongoid.yml)
#   ENVIRONMENT  mongoid environment                  (default test)
#   LOG          set to stream SemanticLogger to stdout

require "benchmark"
require "rocketjob"

COUNT       = Integer(ENV.fetch("COUNT", 1_000_000).to_s.delete("_"))
SLICE_SIZE  = Integer(ENV.fetch("SLICE_SIZE", 1_000).to_s.delete("_"))
THREADS     = Integer(ENV.fetch("THREADS", 1).to_s)
THREAD_LIST = ENV.fetch("THREAD_LIST", "1,4,8,16").split(",").map { |s| Integer(s) }
POLLS       = Integer(ENV.fetch("POLLS", 2_000).to_s)
SERIALIZER  = ENV.fetch("SERIALIZER", "none").to_sym
WRITE_OUT   = ENV.fetch("OUTPUT", "true") != "false"
MODE        = ENV.fetch("MODE", "throughput")
MONGO       = ENV.fetch("MONGO", "test/config/mongoid.yml")
ENVIRONMENT = ENV.fetch("ENVIRONMENT", "test")

SemanticLogger.default_level = :error
SemanticLogger.add_appender(io: $stdout, formatter: :color) if ENV["LOG"]
RocketJob::Config.load!(ENVIRONMENT, MONGO)

# A no-op batch job: `#perform` does nothing, so measured time is pure framework
# overhead (claim slice, deserialize, per-record bookkeeping, serialize output,
# persist, destroy input, and -- in dequeue mode -- re-claim the running job).
class BenchmarkJob < RocketJob::Job
  include RocketJob::Batch

  self.destroy_on_complete = false

  input_category slice_size: 100
  output_category

  def perform(record)
    record
  end
end

def build_job
  job                           = BenchmarkJob.new(log_level: :error)
  job.input_category.slice_size = SLICE_SIZE
  job.input_category.serializer = SERIALIZER
  if WRITE_OUT
    job.output_category.serializer = SERIALIZER
  else
    job.output_categories = []
  end
  job
end

def commas(number)
  number.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse
end

def drop_collections!
  RocketJob::Job.delete_all
  database = RocketJob::Sliced::Slice.collection.database
  database.collections.each do |collection|
    collection.drop if collection.name.start_with?("rocket_job.inputs.", "rocket_job.outputs.")
  end
end

# ------------------------------------------------------------------------------
# throughput: upload COUNT records, then process them all in-process.
#
# Note: in CRuby, in-process worker threads share the GVL, so the CPU-bound
# Mongoid/BSON work does not run in parallel here -- use this mode to track the
# single-worker steady-state rate, not to estimate cluster scaling.
# ------------------------------------------------------------------------------
def run_throughput
  puts "Batch throughput  count=#{commas(COUNT)} slice_size=#{commas(SLICE_SIZE)} " \
       "threads=#{THREADS} serializer=#{SERIALIZER} output=#{WRITE_OUT} ruby=#{RUBY_VERSION}"

  drop_collections!
  job = build_job

  upload = Benchmark.realtime { job.upload { |writer| COUNT.times { |i| writer << i } } }
  job.save!
  puts format("Upload:  %<t>8.3fs  (%<s>s slices, %<r>s rec/s)",
              t: upload, s: commas(job.input.count), r: commas((COUNT / upload).round))

  job.start!
  process = Benchmark.realtime { process_inline(job) }

  job.reload
  puts format("Process: %<t>8.3fs  (%<r>s rec/s on %<n>d thread(s))",
              t: process, r: commas((COUNT / process).round), n: THREADS)
  drop_collections!
end

def process_inline(job)
  if THREADS <= 1
    worker = RocketJob::Worker.new
    worker_loop(job, worker)
    return
  end

  threads = Array.new(THREADS) do |i|
    Thread.new do
      local    = build_job
      local.id = job.id
      local.reload
      worker_loop(local, RocketJob::Worker.new(id: i))
    end
  end
  threads.each(&:join)
end

def worker_loop(job, worker)
  job.rocket_job_work(worker, false) until job.reload.completed?
end

# ------------------------------------------------------------------------------
# micro: isolate the per-slice operations so a regression can be attributed to a
# specific layer (build/serialize, insert, claim, find+parse).
# ------------------------------------------------------------------------------
def run_micro
  reps = [COUNT / SLICE_SIZE, 1_000].min
  puts "Micro per-slice hot path  reps=#{commas(reps)} slice_size=#{commas(SLICE_SIZE)}"

  drop_collections!
  job = build_job
  job.save!
  records = Array.new(SLICE_SIZE) { |i| i }

  Benchmark.bm(28) do |x|
    x.report("build + serialize slice:") { reps.times { build_and_serialize(job, records) } }
    x.report("insert slice:") { reps.times { insert_slice(job, records) } }

    reseed(job, records, reps)
    x.report("claim slice (find+modify):") { reps.times { job.input.next_slice("bench:1") } }

    reseed(job, records, reps)
    x.report("find + parse_records:") { job.input.all.queued.each { |slice| slice.records.size } }
  end
  drop_collections!
end

def build_and_serialize(job, records)
  slice = job.input.new(records: records.dup)
  slice.send(:serialize_records)
end

def insert_slice(job, records)
  job.input.insert(job.input.new(records: records.dup))
end

def reseed(job, records, reps)
  job.input.delete_all
  reps.times { insert_slice(job, records) }
end

# ------------------------------------------------------------------------------
# dequeue: the scenario that regresses at scale. One running batch job, many
# worker threads all polling `find_and_assign_job` (findAndModify on
# rocket_job.jobs). Watch aggregate polls/s stop scaling -- and then drop -- as
# the worker count rises, because every poll write-locks the same document.
# ------------------------------------------------------------------------------
def run_dequeue
  puts "Dequeue contention  one running batch job, polls/thread=#{commas(POLLS)}"
  puts "(tail the mongod log for: \"Caught WriteConflictException\" id 46404 on rocket_job.jobs)"

  drop_collections!
  job = build_job
  job.upload { |writer| SLICE_SIZE.times { |i| writer << i } }
  job.save!
  job.start!
  # `start!` leaves a batch job in sub_state :before; the :before->:processing
  # transition normally happens inside a worker. Force it so the dequeue query
  # actually matches the running batch job (and exercises the join path).
  job.sub_state = :processing
  job.save!
  job.set(worker_name: nil)

  THREAD_LIST.each do |nthreads|
    realtime = Benchmark.realtime { hammer_dequeue(nthreads) }
    total    = POLLS * nthreads
    puts format("threads=%<n>2d  polls=%<p>7s  %<t>6.2fs  %<r>8s polls/s",
                n: nthreads, p: commas(total), t: realtime, r: commas((total / realtime).round))
  end

  # Write evidence: with the contention fix, joining a running batch job is
  # read-only, so worker_name is never re-stamped on the job document.
  job.reload
  puts "job.worker_name after #{commas(POLLS * THREAD_LIST.sum)} joins: #{job.worker_name.inspect} " \
       "(nil => no writes to the job document; non-nil => every poll wrote it)"
  drop_collections!
end

def hammer_dequeue(nthreads)
  threads = Array.new(nthreads) do |i|
    Thread.new do
      worker = RocketJob::Worker.new(id: i, server_name: "bench:#{i}")
      POLLS.times { worker.find_and_assign_job }
    end
  end
  threads.each(&:join)
end

case MODE
when "micro"   then run_micro
when "dequeue" then run_dequeue
else run_throughput
end
