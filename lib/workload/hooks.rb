module Workload
  class Hooks < Redmine::Hook::ViewListener
    render_on :view_issues_sidebar_planning_bottom,
      :partial => 'hooks/view_issues_sidebar_planning_bottom'
  end
end
