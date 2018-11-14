---
layout: default
---

### Rocket Job Enterprise

Rocket Job Enterprise adds the following features to Rocket Job Batch jobs:

* Encryption.
    * Meet compliance regulations.
* Compression.
    * Reduced storage and network requirements.
* Commercial Support.

### Compression

Compression reduces network utilization and disk storage requirements.
Highly recommended when processing large files, or large amounts of data.

~~~ruby
class ReverseJob < RocketJob::Job
  include RocketJob::Batch

  # Compress input and output data
  self.compress = true

  def perform(line)
    line.reverse
  end
end
~~~

### Encryption

By setting the Batch Job attribute `encrypt` to true, input and output data is encrypted.
Encryption helps ensure sensitive data meets compliance requirements both at rest and in-flight.

~~~ruby
class ReverseJob < RocketJob::Job
  include RocketJob::Batch

  # Encrypt input and output data
  self.encrypt = true

  def perform(line)
    line.reverse
  end
end
~~~
