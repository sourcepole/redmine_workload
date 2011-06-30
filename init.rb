require 'redmine'

Redmine::Plugin.register :redmine_workload do
  name 'Workload plugin'
  author 'Sourcepole'
  description 'A plugin for workload diagrams in Redmine'
  version '0.1'

  settings :default => {'workload_measure' => Workload::Workload::MEASURE_FREE_CAPACITY}, :partial => 'settings/workload'

  permission :workload, {:workload => [:show]}, :public => true
  menu :project_menu, :workload, { :controller => 'workload', :action => 'show' }, :caption => :label_workload, :after => :gantt, :param => :project_id
end
