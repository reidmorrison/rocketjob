# Rocket Job
[![Gem Version](https://img.shields.io/gem/v/rocketjob.svg)](https://rubygems.org/gems/rocketjob) [![Downloads](https://img.shields.io/gem/dt/rocketjob.svg)](https://rubygems.org/gems/rocketjob) [![License](https://img.shields.io/badge/license-Apache%202.0-brightgreen.svg)](http://opensource.org/licenses/Apache-2.0) ![](https://img.shields.io/badge/status-Production%20Ready-blue.svg)

**Process millions of records across thousands of workers.**

Rocket Job is a distributed, priority-based, MongoDB-backed batch processing system for Ruby. Run
conventional background jobs, or split a single job's input into slices and process it concurrently
across thousands of workers, spilling from memory to disk so very large files never fall over.

Full documentation is at **[rocketjob.io](https://rocketjob.io/)**.

![Rocket Job](https://rocketjob.io/images/rocket/rocket-icon-512x512.png)

## Documentation

* [Introduction](https://rocketjob.io/) &mdash; what Rocket Job is and why it exists
* [Installation](https://rocketjob.io/installation.html)
* [Programmer's Guide](https://rocketjob.io/guide.html) &mdash; simple jobs
* [Batch Guide](https://rocketjob.io/batch.html) &mdash; parallel batch jobs
* [Included Jobs](https://rocketjob.io/jobs.html) and [Directory Monitor](https://rocketjob.io/dirmon.html)
* [Events](https://rocketjob.io/events.html)
* [Web UI (Mission Control)](https://rocketjob.io/mission_control.html)
* [Deployment](https://rocketjob.io/deployment.html)
* [Architecture and Internals](https://rocketjob.io/architecture.html)
* [API Reference](https://www.rubydoc.info/gems/rocketjob/)

## Support

* Ask questions in [Rocket Job Discussions](https://github.com/reidmorrison/rocketjob/discussions)
* [Report bugs](https://github.com/reidmorrison/rocketjob/issues)

## Upgrading

See the [Upgrading guide](https://rocketjob.io/upgrading.html) for the code and data changes needed
between major versions. Per-release notes are in the
[GitHub Releases](https://github.com/reidmorrison/rocketjob/releases).

## Contributing

Contributions are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) for the development setup and how
to run the test suite, and the [Architecture and Internals](https://rocketjob.io/architecture.html)
page for how Rocket Job is put together.

The documentation site lives in [`docs/`](docs/) as Jekyll markdown. To preview changes locally:

~~~bash
cd docs
bundle update
jekyll serve
~~~

Then open [http://127.0.0.1:4000](http://127.0.0.1:4000) and edit the files under `docs/`.

## Versioning

This project uses [Semantic Versioning](https://semver.org/).

## License

Apache License v2.0. See [LICENSE.txt](LICENSE.txt).

## Author

[Reid Morrison](https://github.com/reidmorrison)

[Contributors](https://github.com/reidmorrison/rocketjob/graphs/contributors)
