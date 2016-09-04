# encoding: UTF-8
module RocketJob
  # Heartbeat
  #
  # Information from the worker as at it's last heartbeat
  class Heartbeat
    include Plugins::Document

    # Time of the last heartbeat received from this worker
    field :updated_at, type: Time

    # Number of threads running as at the last heartbeat interval
    field :active_threads, type: Integer
    # Number of threads in the pool
    #   This number should grow and shrink between 1 and :max_threads
    field :current_threads, type: Integer

    #
    # Process Information. Future.
    #

    # Percentage utilization for the worker process alone
    #field :process_cpu, type: Integer
    # Kilo Bytes used by the worker process (Virtual & Physical)
    #field :process_mem_phys_kb, type: Integer
    #field :process_mem_virt_kb, type: Integer

    #
    # System Information. Future.
    #

    # Percentage utilization for the host machine
    #field :host_cpu, type: Integer
    # Kilo Bytes Available on the host machine (Physical)
    #field :host_mem_avail_phys_kbytes, type: Float
    #field :host_mem_avail_virt_kbytes, type: Float

    # If available
    #field :load_average, type: Float
  end
end

