# Autoload Rufus Scheduler Cron Line parsing code only.
#
# Be sure to require 'rufus-scheduler' if it is being used for
# any other scheduling tasks.
module Rufus
  class Scheduler
    autoload :CronLine, 'rufus/scheduler/cronline'
    autoload :ZoTime, 'rufus/scheduler/zotime'
  end
end
