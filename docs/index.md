---
layout: default
---

<table border="0" width="100%">
  <tr>
    <td>100% Open Source:</td>
    <td><a href="http://www.apache.org/licenses/LICENSE-2.0">Apache License, v2.0</a></td>
  </tr>
  <tr>
    <td>
      Monitoring:
      <ul>
        <li>Web Interface.</li>
        <li>See all running jobs.</li>
        <li>View current status.</li>
      </ul>
    </td>
    <td align="center" width="60%"><img src="images/rjmc_running.png" alt="Running"></td>
  </tr>
  <tr>
    <td>
      Priority based processing.
      <ul>
        <li>Process jobs in business priority order.</li>
        <li>Dynamically change job priority to push through business critical jobs.</li>
      </ul>
    </td>
    <td align="center"><img src="images/rjmc_queued.png" alt="Running"></td>
  </tr>
  <tr>
    <td>
      Cron replacement.
    </td>
    <td align="center"><img src="images/rjmc_scheduled.png" alt="Running"></td>
  </tr>
  <tr>
    <td>
      Familiar interface.
      <ul>
        <li>Similar to ActiveRecord.</li>
      </ul>
    </td>
    <td>
<div class="highlighter-rouge"><pre class="highlight"><code><span class="no">ImportJob</span><span class="p">.</span><span class="nf">create!</span><span class="p">(</span>
  <span class="ss">file_name: </span><span class="s1">"file.csv"</span><span class="p">,</span>
  <span class="ss">priority:  </span><span class="mi">5</span>
<span class="p">)</span>
</code></pre>
</div>
    </td>
  </tr>
  <tr>
    <td>
      Implement behavior.
      <ul>
        <li>#perform</li>
      </ul>
    </td>
    <td>
<div class="highlighter-rouge"><pre class="highlight"><code><span class="k">class</span> <span class="nc">MyJob</span> <span class="o">&lt;</span> <span class="no">RocketJob</span><span class="o">::</span><span class="no">Job</span>
  <span class="k">def</span> <span class="nf">perform</span>
    <span class="c1"># Implement behavior here ...</span>
  <span class="k">end</span>
<span class="k">end</span>
</code></pre>
</div>
    </td>
  </tr>
  <tr>
    <td>
      Fields, with types:
      <ul>
        <li>Array</li>
        <li>Date</li>
        <li>Float</li>
        <li>Hash</li>
        <li>Integer</li>
        <li>Range</li>
        <li>Regexp</li>
        <li>String</li>
        <li>Time</li>
        <li>Etc.</li>
      </ul>
    </td>
    <td>
<div class="highlighter-rouge"><pre class="highlight"><code><span class="k">class</span> <span class="nc">Job</span> <span class="o">&lt;</span> <span class="no">RocketJob</span><span class="o">::</span><span class="no">Job</span>
  <span class="n">field</span> <span class="ss">:login</span><span class="p">,</span> <span class="no">String</span>
  <span class="n">field</span> <span class="ss">:count</span><span class="p">,</span> <span class="no">Integer</span>
  
  <span class="k">def</span> <span class="nf">perform</span>
    <span class="c1"># Implement behavior here ...</span>
  <span class="k">end</span>
<span class="k">end</span>
</code></pre>
</div>
    </td>
  </tr>
  <tr>
    <td>
      Validations:
    </td>
    <td>
<div class="highlighter-rouge"><pre class="highlight"><code><span class="k">class</span> <span class="nc">Job</span> <span class="o">&lt;</span> <span class="no">RocketJob</span><span class="o">::</span><span class="no">Job</span>
  <span class="n">field</span> <span class="ss">:login</span><span class="p">,</span> <span class="no">String</span>
  <span class="n">field</span> <span class="ss">:count</span><span class="p">,</span> <span class="no">Integer</span>

  <span class="k">def</span> <span class="nf">perform</span>
    <span class="c1"># Implement behavior here ...</span>
  <span class="k">end</span>
  
  <span class="n">validates_presence_of</span> <span class="ss">:login</span>
  <span class="n">validates</span> <span class="ss">:count</span><span class="p">,</span> <span class="ss">inclusion: </span><span class="mi">1</span><span class="p">.</span><span class="nf">.</span><span class="mi">100</span>
<span class="k">end</span>
</code></pre>
</div>
    </td>
  </tr>
  <tr>
    <td>
      Callbacks:
      <ul>
        <li>Extensive callback hooks to customize job processing and behavior.</li>
      </ul>
    </td>
    <td>
<div class="highlighter-rouge"><pre class="highlight"><code><span class="k">class</span> <span class="nc">MyJob</span> <span class="o">&lt;</span> <span class="no">RocketJob</span><span class="o">::</span><span class="no">Job</span>
  <span class="n">after_start</span> <span class="ss">:email_started</span>

  <span class="k">def</span> <span class="nf">perform</span>
    <span class="c1"># Implement behavior here ...</span>
  <span class="k">end</span>

  <span class="c1"># Send an email when the job starts</span>
  <span class="k">def</span> <span class="nf">email_started</span>
    <span class="no">MyJobMailer</span><span class="p">.</span><span class="nf">started</span><span class="p">(</span><span class="nb">self</span><span class="p">).</span><span class="nf">deliver_now</span>
  <span class="k">end</span>
<span class="k">end</span>
</code></pre>
</div>
    </td>
  </tr>
  <tr>
    <td>
      Batch Jobs:
      <ul>
        <li>Use many workers to process a single job at the same time.</li>
        <li>Process large files by breaking it up into pieces that can be processed concurrently across all available workers.</li>
      </ul>
    </td>
    <td>
<div class="highlighter-rouge"><pre class="highlight"><code><span class="k">class</span> <span class="nc">ImportPricesJob</span> <span class="o">&lt;</span> <span class="no">RocketJob</span><span class="o">::</span><span class="no">Job</span>
  <span class="n">include</span> <span class="ss">RocketJob::Batch </span>
  
  <span class="k">def</span> <span class="nf">perform</span>(<span class="nb">row</span>)
    <span class="c1"># Each row is a Hash</span>
    <span class="c1"># Load into DB via Active Record</span>
    <span class="no">Price</span><span class="p">.</span><span class="nf">create!</span><span class="p">(</span><span class="nb">row</span><span class="p">)</span>
  <span class="k">end</span>
<span class="k">end</span>
</code></pre>
</div>
<div class="highlighter-rouge"><pre class="highlight"><code><span class="c1"># Upload the file into the Batch Job for processing</span>
job = <span class="nc">ImportPricesJob</span>.new
job.<span class="nf">upload</span>(<span class="s1">"prices.csv"</span>)
job.<span class="nf">save!</span>
</code></pre>
</div>
    </td>
  </tr>
  <tr>
    <td>
      Trigger Jobs when new files arrive:
      <ul>
        <li>Dirmon monitors directories for new files.</li>
        <li>Kicks off a Rocket Job to process the file.</li>
      </ul>
    </td>
    <td align="center"><img src="images/fa-folder-open-128.png" alt="Folder"></td>
  </tr>
  <tr>
    <td>
      High Performance:
      <ul>
        <li>Over <a href="rj_performance.html">1,000</a> jobs per second on a single server.</li>
      </ul>
    </td>
    <td align="center"><img src="images/fa-alarm-clock.png" alt="Folder"></td>
  </tr>
  <tr>
    <td>
      Reliable:
      <ul>
        <li>Reliably process and track every job.</li>
      </ul>
    </td>
    <td align="center"><img src="images/fa-chain.png" alt="Folder"></td>
  </tr>
  <tr>
    <td>
      Scalable:
      <ul>
        <li>Scales from a single worker to thousands of workers across hundreds of servers.</li>
      </ul>
    </td>
    <td align="center"><img src="images/fa-server.png" alt="Folder"> <img src="images/fa-server.png" alt="Folder"> <img src="images/fa-server.png" alt="Folder"></td>
  </tr>
  <tr>
    <td>
      High Performance Metrics and Logging:
      <ul>
        <li>File</li>
        <li>Bugsnag</li>
        <li>Apache Kafka</li>
        <li>ElasticSearch</li>
        <li>MongoDB</li>
        <li>NewRelic</li>
        <li>Splunk</li>
        <li>Syslog (TCP, UDP, & local)</li>
        <li>Etc.</li>
      </ul>
    </td>
    <td align="center"><img src="images/fa-server.png" alt="Folder"></td>
  </tr>
  <tr>
    <td>
      Fully supports and integrates with Rails.
    </td>
    <td align="center"><img src="images/rails-logo.svg" height="128" alt="Rails"></td>
  </tr>
</table>

[0]: http://rocketjob.io
[1]: mission_control.html
[2]: http://rocketjob.github.io/semantic_logger
[3]: http://mongodb.org
[4]: dirmon.html
