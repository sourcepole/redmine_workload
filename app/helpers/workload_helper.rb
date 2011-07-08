module WorkloadHelper

  def workload_zoom_link(workload, in_or_out)
    case in_or_out
    when :in
      if workload.zoom < 4
        link_to_content_update l(:text_zoom_in),
          params.merge(workload.params.merge(:zoom => (workload.zoom+1))),
          :class => 'icon icon-zoom-in'
      else
        content_tag('span', l(:text_zoom_in), :class => 'icon icon-zoom-in')
      end

    when :out
      if workload.zoom > 1
        link_to_content_update l(:text_zoom_out),
          params.merge(workload.params.merge(:zoom => (workload.zoom-1))),
          :class => 'icon icon-zoom-out'
      else
        content_tag('span', l(:text_zoom_out), :class => 'icon icon-zoom-out')
      end
    end
  end

  def workload_value_select(workload)
    content_tag('span', l(:measure) + ": " + content_tag('select', options_for_select(Workload::Workload::measures_for_select, workload.measure), :name => "measure") )
  end

  def render_workload_tooltip(workload)
    @cached_label_date ||= l(:label_date)
    @cached_label_user_capacity ||= l(:user_capacity)
    @cached_label_planned_capacity ||= l(:measure_planned_capacity)
    @cached_label_free_capacity ||= l(:measure_free_capacity)
    @cached_label_workload ||= l(:measure_workload)
    @cached_label_availability ||= l(:measure_availability)
    @cached_label_issue ||= l(:label_issue)
    @cached_label_issues ||= l(:label_issue_plural)
    @cached_label_overdue ||= l(:label_overdue)

    @tooltip_workload = workload
    @issues = workload[:issues] || []
    @overdue_issues = workload[:overdue_issues] || []
    render :partial => 'workload/tooltip'
  end
  
  def format_number(value)
    number_with_precision(value, :precision => 2, :separator => '.')
  end

  def workload_issue_line(issue)
    "#{link_to_issue(issue)} (#{issue.status}, #{issue.priority})"
  end

end
