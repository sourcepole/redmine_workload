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

  def render_workload_tooltip(workload)
    # TODO: translations
    # TODO: links to issues
    "<strong>Date</strong>: #{workload[:date]}<br/>" +
    "<strong>Workload</strong>: #{workload[:workload]}<br/>" +
    "<strong>User capacity</strong>: #{workload[:user_capacity]}<br/>" +
    "<strong>Value</strong>: #{workload[:value]}<br/>"
  end

end
