require_dependency 'redmine/helpers/gantt'

module GanttPatch
  def self.included(base) # :nodoc:
    base.send(:include, InstanceMethods)

    base.class_eval do
      alias_method_chain :initialize, :month_year_filter
    end
  end

  module InstanceMethods
    def initialize_with_month_year_filter(options={}, &block)
      # load gantt parameters from user preferences (month and year)
      options[:month] ||= User.current.pref[:gantt_month]
      options[:year] ||= User.current.pref[:gantt_year]

      initialize_without_month_year_filter(options, &block)

      # Save gantt parameters as user preference (month and year)
      if (User.current.logged? && (@month_from != User.current.pref[:gantt_month] || @year_from != User.current.pref[:gantt_year]))
        User.current.pref[:gantt_month] = @month_from
        User.current.pref[:gantt_year] = @year_from
        User.current.preference.save
      end
    end
  end

end

require 'dispatcher'
Dispatcher.to_prepare do
  unless Redmine::Helpers::Gantt.included_modules.include? GanttPatch
    Redmine::Helpers::Gantt.send(:include, GanttPatch)
  end
end
