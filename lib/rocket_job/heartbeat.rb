# encoding: UTF-8
module RocketJob
  # Heartbeat
  #
  # Information from the worker as at it's last heartbeat
  class Heartbeat
    include MongoMapper::EmbeddedDocument

    embedded_in :worker

    # Time of the last heartbeat received from this worker
    key :updated_at,                 Time

    # Number of threads running as at the last heartbeat interval
    key :active_threads,             Integer
    # Number of threads in the pool
    #   This number should grow and shrink between 1 and :max_threads
    key :current_threads,             Integer

    #
    # Process Information
    #

    # Percentage utilization for the worker process alone
    key :process_cpu,                Integer
    # Kilo Bytes used by the worker process (Virtual & Physical)
    key :process_mem_phys_kb,        Integer
    key :process_mem_virt_kb,        Integer

    #
    # System Information
    #

    # Percentage utilization for the host machine
    key :host_cpu,                   Integer
    # Kilo Bytes Available on the host machine (Physical)
    key :host_mem_avail_phys_kbytes, Float
    key :host_mem_avail_virt_kbytes, Float

    # If available
    key :load_average,               Float
  end
end

