module RocketJob
  module Sliced
    autoload :BZip2OutputSlice, "rocket_job/sliced/bzip2_output_slice"
    autoload :CompressedSlice, "rocket_job/sliced/compressed_slice"
    autoload :EncryptedBZip2OutputSlice, "rocket_job/sliced/encrypted_bzip2_output_slice"
    autoload :EncryptedSlice, "rocket_job/sliced/encrypted_slice"
    autoload :Input, "rocket_job/sliced/input"
    autoload :Output, "rocket_job/sliced/output"
    autoload :Slice, "rocket_job/sliced/slice"
    autoload :Slices, "rocket_job/sliced/slices"
    autoload :Store, "rocket_job/sliced/store"

    module Writer
      autoload :Input, "rocket_job/sliced/writer/input"
      autoload :Output, "rocket_job/sliced/writer/output"
    end
  end
end
