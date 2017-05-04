---
layout: default
---

<table border="0" width="100%">
  <tr>
    <td align="center" width="60%"><a>Cost: $0</a></td>
    <td>
      Free.
      <ul>
        <li>Open Source.</li>
        <li>Community support.</li>
      </ul>
    </td>
  </tr>
  <tr>
    <td align="center" width="60%"><img src="images/rjmc_running.png" alt="Running"></td>
    <td>
      Monitoring.
      <ul>
        <li>Web Interface - Rocket Job Mission Control.</li>
        <li>Monitor and manage every job in the system.</li>
        <li>View current status.</li>
      </ul>
    </td>
  </tr>
  <tr>
    <td align="center"><img src="images/rjmc_queued.png" alt="Running"></td>
    <td>
      Priority based processing.
      <ul>
        <li>Process jobs in business priority order.</li>
        <li>Dynamically change job priority to push through business critical jobs.</li>
      </ul>
    </td>
  </tr>
  <tr>
    <td align="center"><img src="images/rjmc_scheduled.png" alt="Running"></td>
    <td>
      Cron replacement.
    </td>
  </tr>
  <tr>
    <td>
<div class="highlighter-rouge"><pre class="highlight"><code><span class="k">class</span> <span class="nc">Job</span> <span class="o">&lt;</span> <span class="no">RocketJob</span><span class="o">::</span><span class="no">Job</span>
  <span class="n">key</span> <span class="ss">:login</span><span class="p">,</span> <span class="no">String</span>
  <span class="n">key</span> <span class="ss">:count</span><span class="p">,</span> <span class="no">Integer</span>

  <span class="n">validates_presence_of</span> <span class="ss">:login</span>
  <span class="n">validates</span> <span class="ss">:count</span><span class="p">,</span> <span class="ss">inclusion: </span><span class="mi">1</span><span class="p">.</span><span class="nf">.</span><span class="mi">100</span>
<span class="k">end</span>
</code></pre>
</div>
    </td>
    <td>
      Validations.
      <ul>
        <li>Validate job parameters when the job is created.</li>
      </ul>
    </td>
  </tr>
  <tr>
    <td>
<div class="highlighter-rouge"><pre class="highlight"><code><span class="k">class</span> <span class="nc">MyJob</span> <span class="o">&lt;</span> <span class="no">RocketJob</span><span class="o">::</span><span class="no">Job</span>
  <span class="n">after_start</span> <span class="ss">:email_started</span>

  <span class="k">def</span> <span class="nf">perform</span>
  <span class="k">end</span>

  <span class="c1"># Send an email when the job starts</span>
  <span class="k">def</span> <span class="nf">email_started</span>
    <span class="no">MyJob</span><span class="p">.</span><span class="nf">started</span><span class="p">(</span><span class="nb">self</span><span class="p">).</span><span class="nf">deliver</span>
  <span class="k">end</span>
<span class="k">end</span>
</code></pre>
</div>
    </td>
    <td>
      Callbacks.
      <ul>
        <li>Extensive callback hooks to customize job processing and behavior.</li>
        <li>Similar to Middleware.</li>
      </ul>
    </td>
  </tr>
  <tr>
    <td>
<div class="highlighter-rouge"><pre class="highlight"><code><span class="no">ImportJob</span><span class="p">.</span><span class="nf">create!</span><span class="p">(</span>
  <span class="ss">file_name: </span><span class="s1">'file.csv'</span><span class="p">,</span>
  <span class="ss">priority:  </span><span class="mi">5</span>
<span class="p">)</span>
</code></pre>
</div>
    </td>
    <td>
      Familiar interface.
      <ul>
        <li>Similar interface to ActiveRecord models.</li>
      </ul>
    </td>
  </tr>
  <tr>
    <td align="center"><img src="images/fa-folder-open-128.png" alt="Folder"></td>
    <td>
      Trigger Jobs when new files arrive.
      <ul>
        <li>Dirmon monitors directories for new files.</li>
        <li>Kicks off a Rocket Job to process the file.</li>
      </ul>
    </td>
  </tr>
  <tr>
    <td align="center"><img src="images/fa-alarm-clock.png" alt="Folder"></td>
    <td>
      High Performance.
      <ul>
        <li>Over <a href="rj_performance.html">1,000</a> jobs per second on a single server.</li>
      </ul>
    </td>
  </tr>
  <tr>
    <td align="center"><img src="images/fa-chain.png" alt="Folder"></td>
    <td>
      Reliable.
      <ul>
        <li>Reliably process and track every job.</li>
      </ul>
    </td>
  </tr>
  <tr>
    <td align="center"><img src="images/fa-server.png" alt="Folder"> <img src="images/fa-server.png" alt="Folder"> <img src="images/fa-server.png" alt="Folder"></td>
    <td>
      Scalable.
      <ul>
        <li>Scales from a single worker to thousands of workers across hundreds of servers.</li>
      </ul>
    </td>
  </tr>
  <tr>
    <td align="center"><img src="images/rails-logo.svg" height="128" alt="Rails"></td>
    <td>
      Fully supports and integrates with Rails.
    </td>
  </tr>
  <tr>
    <td align="center"><img src="images/ruby.png" alt="Ruby"></td>
    <td>
      Can run standalone on Ruby.
    </td>
  </tr>
</table>

### Example:

~~~ruby
class ImportJob < RocketJob::Job
  # Create a property called `file_name` of type String
  field :file_name, type: String

  def perform
    # Perform work here, such as processing a large file
    puts "The file_name is #{file_name}"
  end
end
~~~

Queue the job for processing:

~~~ruby
ImportJob.create!(file_name: 'file.csv')
~~~

### [Next: Web UI ==>](mission_control.html)

[0]: http://rocketjob.io
[1]: mission_control.html
[2]: http://rocketjob.github.io/semantic_logger
[3]: http://mongodb.org
[4]: dirmon.html
