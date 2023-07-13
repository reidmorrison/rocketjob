# Contributing

Welcome to Rocket Job, great to have you on-board. :tada:

To get you started here are some pointers. 

## Questions

Please do not open issues for questions, use the discussions feature in Github:
https://github.com/reidmorrison/rocketjob/discussions

## Open Source

#### Early Adopters

Great to have you onboard, looking forward to your help and feedback.

#### Late Adopters

Rocket Job is open source code, the author and contributors do this work when we have the "free time" to do so.

We are not here to write code for some random edge case that you may have. That is the point of Pull Requests
where you can contribute your own enhancements.

## Documentation

Documentation updates are welcomed by all users of Rocket Job.

#### Small changes

For a quick and fairly simple documentation fix the changes can be made entirely online in github.
 
1. Fork the repository in github.
2. Look for the markdown file that matches the documentation page to be updated under the `docs` subdirectory.
3. Click Edit.
4. Make the change and select preview to see what the changes would look like.
5. Save the change with a commit message.
6. Submit a Pull Request back to the Rocket Job repository. 

#### Complete Setup

To make multiple changes to the documentation, add new pages or just to have a real preview of what the
documentation would look like locally after any changes.

1. Fork the repository in github.
2. Clone the repository to your local machine.
3. Change into the documentation directory.

       cd rocketjob/docs
       
4. Install required gems

       bundle update
       
5. Start the Jekyll server

       jekyll s

6. Open a browser to: http://127.0.0.1:4000

7. Navigate around and find the page to edit. The url usually lines up with the markdown file that
   contains the corresponding text.
   
8. Edit the files ending in `.md` and refresh the page in the web browser to see the change.

9. Once change are complete commit the changes.

10. Push the changes to your forked repository.

11. Submit a Pull Request back to the Rocket Job repository. 

## Code Changes

Since changes cannot be made directly to the Rocket Job repository, fork it to your own account on Github. 

1. Fork the repository in github.
2. Clone the repository to your local machine.
3. Change into the Rocket Job directory.

       cd rocketjob
       
4. Install required gems

       bundle update
       
5. Run basic tests

       bundle exec rake test

6. When making a bug fix it is recommended to update the test first, ensure the test fails, and only then
   make the codefix.

7. Once the tests pass and all code changes are complete, commit the changes.
   
8. Push changes to your forked repository.

9. Submit a Pull Request back to the Rocket Job repository. 


### Full Testing

The above code change steps use the packages in Gemfile. When running all of the tests it needs to run
tests against all supported gemsets. Appraisal is used manage multiple gemfiles. 

Install all needed gems to run the tests:

    appraisal install

The gems are installed into the global gem list.
The Gemfiles in the `gemfiles` folder are also re-generated.

#### Run Tests

For all supported Rails/ActiveRecord versions:

    bundle exec rake

Or for specific version one:

    appraisal moingod_7_1 rake

Or for one particular test file

    appraisal mongoid_7_1 ruby -I"test" test/job_test.rb

Or down to one test case

    appraisal mongoid_7_1 ruby -I"test" test/job_test.rb -n "/.requeue_dead_server/"

## Contributor Code of Conduct

As contributors and maintainers of this project, and in the interest of fostering an open and welcoming community, we pledge to respect all people who contribute through reporting issues, posting feature requests, updating documentation, submitting pull requests or patches, and other activities.

We are committed to making participation in this project a harassment-free experience for everyone, regardless of level of experience, gender, gender identity and expression, sexual orientation, disability, personal appearance, body size, race, ethnicity, age, religion, or nationality.

Examples of unacceptable behavior by participants include:

* The use of sexualized language or imagery
* Personal attacks
* Trolling or insulting/derogatory comments
* Public or private harassment
* Publishing other's private information, such as physical or electronic addresses, without explicit permission
* Other unethical or unprofessional conduct.

Project maintainers have the right and responsibility to remove, edit, or reject comments, commits, code, wiki edits, issues, and other contributions that are not aligned to this Code of Conduct. By adopting this Code of Conduct, project maintainers commit themselves to fairly and consistently applying these principles to every aspect of managing this project. Project maintainers who do not follow or enforce the Code of Conduct may be permanently removed from the project team.

This code of conduct applies both within project spaces and in public spaces when an individual is representing the project or its community.

Instances of abusive, harassing, or otherwise unacceptable behavior may be reported by opening an issue or contacting one or more of the project maintainers.

This Code of Conduct is adapted from the [Contributor Covenant](http://contributor-covenant.org), version 1.2.0, available at [http://contributor-covenant.org/version/1/2/0/](http://contributor-covenant.org/version/1/2/0/)
