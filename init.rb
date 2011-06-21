require 'redmine'

Redmine::Plugin.register :redmine_workload do
  name 'Workload plugin'
  author 'Sourcepole'
  description 'A plugin for workload diagrams in Redmine'
  version '0.1'

  permission :workload, {:workload => [:show]}, :public => true
  menu :project_menu, :workload, { :controller => 'workload', :action => 'show' }, :caption => 'Workload', :after => :gantt, :param => :project_id
end
