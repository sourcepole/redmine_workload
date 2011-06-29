module Workload
  class Workload
    unloadable

    include ERB::Util
    include Redmine::I18n

    # :nodoc:
    # Some utility methods for the PDF export
    class PDF
      MaxCharactorsForSubject = 45
      TotalWidth = 280
      LeftPaneWidth = 100

      def self.right_pane_width
        TotalWidth - LeftPaneWidth
      end
    end

    attr_reader :year_from, :month_from, :date_from, :date_to, :zoom, :months, :truncated, :max_rows
    attr_accessor :query
    attr_accessor :view
    attr_accessor :measure

    MEASURE_PLANNED_CAPACITY = 1
    MEASURE_FREE_CAPACITY = 2
    MEASURE_WORKLOAD = 3
    MEASURE_AVAILABILITY = 4

    def initialize(options={})
      options = options.dup

      if options[:year] && options[:year].to_i >0
        @year_from = options[:year].to_i
        if options[:month] && options[:month].to_i >=1 && options[:month].to_i <= 12
          @month_from = options[:month].to_i
        else
          @month_from = 1
        end
      else
        @month_from ||= Date.today.month
        @year_from ||= Date.today.year
      end

      zoom = (options[:zoom] || User.current.pref[:gantt_zoom]).to_i
      @zoom = (zoom > 0 && zoom < 5) ? zoom : 2
      months = (options[:months] || User.current.pref[:gantt_months]).to_i
      @months = (months > 0 && months < 25) ? months : 6

      # Save workload parameters as user preference (zoom and months count)
      if (User.current.logged? && (@zoom != User.current.pref[:gantt_zoom] || @months != User.current.pref[:gantt_months]))
        User.current.pref[:gantt_zoom], User.current.pref[:gantt_months] = @zoom, @months
        User.current.preference.save
      end

      @date_from = Date.civil(@year_from, @month_from, 1)
      @date_to = (@date_from >> @months) - 1

      @subjects = ''
      @lines = ''
      @number_of_rows = nil

      @issue_ancestors = []

      @truncated = false
      if options.has_key?(:max_rows)
        @max_rows = options[:max_rows]
      else
        @max_rows = Setting.gantt_items_limit.blank? ? nil : Setting.gantt_items_limit.to_i
      end

      if options[:measure]
        @measure = options[:measure].to_i
      else
        @measure = MEASURE_FREE_CAPACITY
      end
    end

    def common_params
      { :controller => 'workload', :action => 'show' }
    end

    def params
      common_params.merge({  :zoom => zoom, :year => year_from, :month => month_from, :months => months })
    end

    def params_previous
      common_params.merge({:year => (date_from << months).year, :month => (date_from << months).month, :zoom => zoom, :months => months })
    end

    def params_next
      common_params.merge({:year => (date_from >> months).year, :month => (date_from >> months).month, :zoom => zoom, :months => months })
    end

    def measures_for_select
      [
        [l(:measure_planned_capacity), MEASURE_PLANNED_CAPACITY],
        [l(:measure_free_capacity), MEASURE_FREE_CAPACITY],
        [l(:measure_workload), MEASURE_WORKLOAD],
        [l(:measure_availability), MEASURE_AVAILABILITY]
      ]
    end

    def current_measure_text
      case @measure
      when MEASURE_PLANNED_CAPACITY
        l(:measure_planned_capacity)
      when MEASURE_FREE_CAPACITY
        l(:measure_free_capacity)
      when MEASURE_WORKLOAD
        l(:measure_workload)
      when MEASURE_AVAILABILITY
        l(:measure_availability)
      end
    end

    # Returns the number of rows that will be rendered on the workload chart
    def number_of_rows
      return @number_of_rows if @number_of_rows

      rows = users.count
      rows > @max_rows ? @max_rows : rows
    end

    # Renders the subjects of the workload chart, the left side.
    def subjects(options={})
      render(options.merge(:only => :subjects)) unless @subjects_rendered
      @subjects
    end

    # Renders the lines of the workload chart, the right side
    def lines(options={})
      render(options.merge(:only => :lines)) unless @lines_rendered
      @lines
    end

    def users
      User.active.all(:order => "lastname")
    end

    def render(options={})
      options = {:top => 0, :top_increment => 20, :indent_increment => 20, :render => :subject, :format => :html}.merge(options)
      indent = options[:indent] || 4

      @subjects = '' unless options[:only] == :lines
      @lines = '' unless options[:only] == :subjects
      @number_of_rows = 0

      level = 0
      users.each do |user|
        options[:indent] = indent + level * options[:indent_increment]
        render_user(user, options)
        break if abort?
      end

      @subjects_rendered = true unless options[:only] == :lines
      @lines_rendered = true unless options[:only] == :subjects

      render_end(options)
    end

    def render_user(user, options={})
      subject_for_user(user, options) unless options[:only] == :lines
      line_for_user(user, options) unless options[:only] == :subjects

      options[:top] += options[:top_increment]
      @number_of_rows += 1
    end

    def subject_for_user(user, options={})
      case options[:format]
      when :html
        subject = "<span class='icon icon-user'>"
        subject << view.link_to_user(user)
        subject << '</span>'
        html_subject(options, subject, :css => "project-name")
      when :image
        image_subject(options, user.name)
      when :pdf
        pdf_new_page?(options)
        pdf_subject(options, user.name)
      end
    end

    def line_for_user(user, options={})
      options[:zoom] ||= 1
      options[:g_width] ||= (self.date_to - self.date_from + 1) * options[:zoom]

      # TODO: filter issues by visible date range, closed
      issues = @query.issues(
        :conditions => ["assigned_to_id=? AND due_date IS NOT NULL AND estimated_hours IS NOT NULL", user.id],
        :order => "start_date"
      )

      # user defined working times (wday 0 = sunday)
      user_capacities = [0.0, 8.0, 8.0, 8.0, 8.0, 8.0, 0.0] # FIXME: customize per user

      # init days
      workload_days = []
      date = self.date_from
      while date <= self.date_to
        coords = coordinates(date, date, nil, options[:zoom])
        workload_days << {:html_coords => coords, :issues_effort => 0, :user_capacity => user_capacities[date.wday], :date => date}
        date += 1
      end

      # apply user issues
      issues.each do |issue|
        # skip parent issues
        next unless issue.leaf?

        apply_issue_effort(issue, workload_days, Date.today)
      end

      workload_days.each do |workload|
        # TODO: skip free days?
        next if workload[:user_capacity] == 0 || workload[:date] < Date.today

        calculate_measures(workload)

        # select measure for display
        case @measure
        when MEASURE_PLANNED_CAPACITY
#          workload[:value] = workload[:measure][:planned_capacity] # FIXME: style for absolute values, show relative value for now
          workload[:value] = workload[:measure][:workload]
        when MEASURE_FREE_CAPACITY
#          workload[:value] = workload[:measure][:free_capacity] # FIXME: style for absolute values, show relative value for now
          workload[:value] = workload[:measure][:availability]
        when MEASURE_WORKLOAD
          workload[:value] = workload[:measure][:workload]
        when MEASURE_AVAILABILITY
          workload[:value] = workload[:measure][:availability]
        else
          workload[:value] = 0
        end

        # TODO: styles for absolute measure values

        case options[:format]
        when :html
          html_workload(options, workload)
        when :image
          image_workload(options, workload)
        when :pdf
          pdf_workload(options, workload)
        end
      end
    end

    # Calculate effort distribution of issue in remaining duration from workload_start_date
    def apply_issue_effort(issue, workload_days, workload_start_date)
      # workload days range
      workload_days_date_from = workload_days.first[:date]
      workload_days_date_to = workload_days.last[:date]

      # clamp dates
      from_date = issue.start_date
      if from_date < workload_days_date_from
        from_date = workload_days_date_from
      end
      if from_date < workload_start_date
        from_date = workload_start_date
      end

      to_date = issue.due_date
      if to_date > workload_days_date_to
        to_date = workload_days_date_to
      end

      # get total user capacity in remaining duration
      total_user_capacity = 0
      date = from_date
      while date <= issue.due_date
        index = date - workload_days_date_from
        total_user_capacity += workload_days[index][:user_capacity]
        date += 1
      end

      # apply issue effort
      issue_remaining_hours = issue.estimated_hours - issue.spent_hours
      if issue.due_date < workload_start_date
        # issue is overdue, add to first day
        # TODO: overdue marker?
        index = from_date - workload_days_date_from
        workload_days[index][:issues_effort] += issue_remaining_hours
        workload_days[index][:overdue] = true
      else
        # split issue effort per day according to user capacity distribution
        date = from_date
        while date <= to_date
          index = date - workload_days_date_from
          workload_days[index][:issues_effort] += workload_days[index][:user_capacity] / total_user_capacity * issue_remaining_hours
          date += 1
        end
      end
    end

    def calculate_measures(workload)
      workload[:measure] = {}
      workload[:measure][:planned_capacity] = workload[:issues_effort]
      workload[:measure][:free_capacity] = workload[:user_capacity] - workload[:issues_effort]
      if workload[:user_capacity] != 0
        workload[:measure][:workload] = workload[:issues_effort] / workload[:user_capacity] * 100
      else
        workload[:measure][:workload] = 0
      end
      if workload[:user_capacity] != 0
        workload[:measure][:availability] = 100 - workload[:measure][:workload]
      else
        workload[:measure][:availability] = 0
      end
    end

    def render_end(options={})
      case options[:format]
      when :pdf
        options[:pdf].Line(15, options[:top], PDF::TotalWidth, options[:top])
      end
    end

    # Generates a workload image
    # Only defined if RMagick is avalaible
    def to_image(format='PNG')
      date_to = (@date_from >> @months)-1
      show_weeks = @zoom > 1
      show_days = @zoom > 2

      subject_width = 400
      header_height = 18
      # width of one day in pixels
      zoom = @zoom*2
      g_width = (@date_to - @date_from + 1)*zoom
      g_height = 20 * number_of_rows + 30
      headers_height = (show_weeks ? 2*header_height : header_height)
      height = g_height + headers_height

      imgl = Magick::ImageList.new
      imgl.new_image(subject_width+g_width+1, height)
      gc = Magick::Draw.new

      # Subjects
      gc.stroke('transparent')
      subjects(:image => gc, :top => (headers_height + 20), :indent => 4, :format => :image)

      # Months headers
      month_f = @date_from
      left = subject_width
      @months.times do
        width = ((month_f >> 1) - month_f) * zoom
        gc.fill('white')
        gc.stroke('grey')
        gc.stroke_width(1)
        gc.rectangle(left, 0, left + width, height)
        gc.fill('black')
        gc.stroke('transparent')
        gc.stroke_width(1)
        gc.text(left.round + 8, 14, "#{month_f.year}-#{month_f.month}")
        left = left + width
        month_f = month_f >> 1
      end

      # Weeks headers
      if show_weeks
        left = subject_width
        height = header_height
        if @date_from.cwday == 1
            # date_from is monday
              week_f = date_from
        else
            # find next monday after date_from
          week_f = @date_from + (7 - @date_from.cwday + 1)
          width = (7 - @date_from.cwday + 1) * zoom
              gc.fill('white')
              gc.stroke('grey')
              gc.stroke_width(1)
              gc.rectangle(left, header_height, left + width, 2*header_height + g_height-1)
          left = left + width
        end
        while week_f <= date_to
          width = (week_f + 6 <= date_to) ? 7 * zoom : (date_to - week_f + 1) * zoom
              gc.fill('white')
              gc.stroke('grey')
              gc.stroke_width(1)
              gc.rectangle(left.round, header_height, left.round + width, 2*header_height + g_height-1)
              gc.fill('black')
              gc.stroke('transparent')
              gc.stroke_width(1)
              gc.text(left.round + 2, header_height + 14, week_f.cweek.to_s)
          left = left + width
          week_f = week_f+7
        end
      end

      # Days details (week-end in grey)
      if show_days
        left = subject_width
        height = g_height + header_height - 1
        wday = @date_from.cwday
        (date_to - @date_from + 1).to_i.times do
            width =  zoom
            gc.fill(wday == 6 || wday == 7 ? '#eee' : 'white')
            gc.stroke('#ddd')
            gc.stroke_width(1)
            gc.rectangle(left, 2*header_height, left + width, 2*header_height + g_height-1)
            left = left + width
            wday = wday + 1
            wday = 1 if wday > 7
        end
      end

      # border
      gc.fill('transparent')
      gc.stroke('grey')
      gc.stroke_width(1)
      gc.rectangle(0, 0, subject_width+g_width, headers_height)
      gc.stroke('black')
      gc.rectangle(0, 0, subject_width+g_width, g_height+ headers_height-1)

      # content
      top = headers_height + 20

      gc.stroke('transparent')
      lines(:image => gc, :top => top, :zoom => zoom, :subject_width => subject_width, :format => :image)

      # today red line
      if Date.today >= @date_from and Date.today <= date_to
        gc.stroke('red')
        x = (Date.today-@date_from+1)*zoom + subject_width
        gc.line(x, headers_height, x, headers_height + g_height-1)
      end

      gc.draw(imgl)
      imgl.format = format
      imgl.to_blob
    end if Object.const_defined?(:Magick)

    def to_pdf
      pdf = ::Redmine::Export::PDF::ITCPDF.new(current_language)
      pdf.SetTitle("#{l(:label_workload)} - #{current_measure_text}")
      pdf.alias_nb_pages
      pdf.footer_date = format_date(Date.today)
      pdf.AddPage("L")
      pdf.SetFontStyle('B',12)
      pdf.SetX(15)
      pdf.RDMCell(PDF::LeftPaneWidth, 20, "#{l(:label_workload)} - #{current_measure_text}")
      pdf.Ln
      pdf.SetFontStyle('B',9)

      subject_width = PDF::LeftPaneWidth
      header_height = 5

      headers_height = header_height
      show_weeks = false
      show_days = false

      if self.months < 7
        show_weeks = true
        headers_height = 2*header_height
        if self.months < 3
          show_days = true
          headers_height = 3*header_height
        end
      end

      g_width = PDF.right_pane_width
      zoom = (g_width) / (self.date_to - self.date_from + 1)
      g_height = 120
      t_height = g_height + headers_height

      y_start = pdf.GetY

      # Months headers
      month_f = self.date_from
      left = subject_width
      height = header_height
      self.months.times do
        width = ((month_f >> 1) - month_f) * zoom
        pdf.SetY(y_start)
        pdf.SetX(left)
        pdf.RDMCell(width, height, "#{month_f.year}-#{month_f.month}", "LTR", 0, "C")
        left = left + width
        month_f = month_f >> 1
      end

      # Weeks headers
      if show_weeks
        left = subject_width
        height = header_height
        if self.date_from.cwday == 1
          # self.date_from is monday
          week_f = self.date_from
        else
          # find next monday after self.date_from
          week_f = self.date_from + (7 - self.date_from.cwday + 1)
          width = (7 - self.date_from.cwday + 1) * zoom-1
          pdf.SetY(y_start + header_height)
          pdf.SetX(left)
          pdf.RDMCell(width + 1, height, "", "LTR")
          left = left + width+1
        end
        while week_f <= self.date_to
          width = (week_f + 6 <= self.date_to) ? 7 * zoom : (self.date_to - week_f + 1) * zoom
          pdf.SetY(y_start + header_height)
          pdf.SetX(left)
          pdf.RDMCell(width, height, (width >= 5 ? week_f.cweek.to_s : ""), "LTR", 0, "C")
          left = left + width
          week_f = week_f+7
        end
      end

      # Days headers
      if show_days
        left = subject_width
        height = header_height
        wday = self.date_from.cwday
        pdf.SetFontStyle('B',7)
        (self.date_to - self.date_from + 1).to_i.times do
          width = zoom
          pdf.SetY(y_start + 2 * header_height)
          pdf.SetX(left)
          pdf.RDMCell(width, height, day_name(wday).first, "LTR", 0, "C")
          left = left + width
          wday = wday + 1
          wday = 1 if wday > 7
        end
      end

      pdf.SetY(y_start)
      pdf.SetX(15)
      pdf.RDMCell(subject_width+g_width-15, headers_height, "", 1)

      # Tasks
      top = headers_height + y_start
      options = {
        :top => top,
        :zoom => zoom,
        :subject_width => subject_width,
        :g_width => g_width,
        :indent => 0,
        :indent_increment => 5,
        :top_increment => 5,
        :format => :pdf,
        :pdf => pdf
      }
      render(options)
      pdf.Output
    end

    private

    def coordinates(start_date, end_date, progress, zoom=nil)
      zoom ||= @zoom

      coords = {}
      if start_date && end_date && start_date < self.date_to && end_date > self.date_from
        if start_date > self.date_from
          coords[:start] = start_date - self.date_from
          coords[:bar_start] = start_date - self.date_from
        else
          coords[:bar_start] = 0
        end
        if end_date < self.date_to
          coords[:end] = end_date - self.date_from
          coords[:bar_end] = end_date - self.date_from + 1
        else
          coords[:bar_end] = self.date_to - self.date_from + 1
        end

        if progress
          progress_date = start_date + (end_date - start_date + 1) * (progress / 100.0)
          if progress_date > self.date_from && progress_date > start_date
            if progress_date < self.date_to
              coords[:bar_progress_end] = progress_date - self.date_from
            else
              coords[:bar_progress_end] = self.date_to - self.date_from + 1
            end
          end

          if progress_date < Date.today
            late_date = [Date.today, end_date].min
            if late_date > self.date_from && late_date > start_date
              if late_date < self.date_to
                coords[:bar_late_end] = late_date - self.date_from + 1
              else
                coords[:bar_late_end] = self.date_to - self.date_from + 1
              end
            end
          end
        end
      end

      # Transforms dates into pixels witdh
      coords.keys.each do |key|
        coords[key] = (coords[key] * zoom)
      end
      coords
    end

    def abort?
      if @max_rows && @number_of_rows >= @max_rows
        @truncated = true
      end
    end

    def pdf_new_page?(options)
      if options[:top] > 180
        options[:pdf].Line(15, options[:top], PDF::TotalWidth, options[:top])
        options[:pdf].AddPage("L")
        options[:top] = 15
        options[:pdf].Line(15, options[:top] - 0.1, PDF::TotalWidth, options[:top] - 0.1)
      end
    end

    def html_subject(params, subject, options={})
      style = "position: absolute;top:#{params[:top]}px;left:#{params[:indent]}px;"
      style << "width:#{params[:subject_width] - params[:indent]}px;" if params[:subject_width]

      output = view.content_tag 'div', subject, :class => options[:css], :style => style, :title => options[:title]
      @subjects << output
      output
    end

    def pdf_subject(params, subject, options={})
      params[:pdf].SetY(params[:top])
      params[:pdf].SetX(15)

      char_limit = PDF::MaxCharactorsForSubject - params[:indent]
      params[:pdf].RDMCell(params[:subject_width]-15, 5, (" " * params[:indent]) +  subject.to_s.sub(/^(.{#{char_limit}}[^\s]*\s).*$/, '\1 (...)'), "LR")

      params[:pdf].SetY(params[:top])
      params[:pdf].SetX(params[:subject_width])
      params[:pdf].RDMCell(params[:g_width], 5, "", "LR")
    end

    def image_subject(params, subject, options={})
      params[:image].fill('black')
      params[:image].stroke('transparent')
      params[:image].stroke_width(1)
      params[:image].text(params[:indent], params[:top] + 2, subject)
    end

    def html_workload(params, workload)
      output = ''

      coords = workload[:html_coords]
      value = workload[:value]

      if coords[:bar_start] && coords[:bar_end]
        # calculate style bin
        bin = (value/25).floor * 25
        workload_class = "workload_#{bin}"
        if bin > 100
          workload_class = "workload_full"
        elsif bin < 0
          workload_class = "workload_empty"
        end
        
        # bar
        output << "<div style='top:#{ params[:top] }px;left:#{ coords[:bar_start] }px;width:#{ coords[:bar_end] - coords[:bar_start] - 2}px;' class='workload #{workload_class}'>&nbsp;</div>"

        # tooltip
        if params[:zoom] >= 4
          output << "<div class='tooltip' style='position: absolute;top:#{ params[:top] }px;left:#{ coords[:bar_start] }px;width:#{ coords[:bar_end] - coords[:bar_start] }px;height:12px;'>"
          output << '<span class="tip">'
          output << view.render_workload_tooltip(workload)
          output << "</span></div>"
        end
      end

      # overdue
      if workload[:overdue] && coords[:start]
        output << "<div style='top:#{ params[:top] }px;left:#{ coords[:start] }px;width:15px;' class='workload workload_overdue'>&nbsp;</div>"
      end

      @lines << output
      output
    end

    def image_workload(params, workload)
      coords = workload[:html_coords]
      value = workload[:value]
      height = 6 # params[:height] || 6 # TODO: const?

      if coords[:bar_start] && coords[:bar_end]
        colors = ['#FF0000', '#FFC000', '#FFFF00', '#C0FF00', '#00FF00', '#00FF00', '#FF0000']
        bin = (value/25).floor
        if bin > 4
          color = colors[5]
        elsif bin < 0
          color = colors[6]
        else
          color = colors[bin]
        end

        # bar
        params[:image].fill(color)
        params[:image].stroke("#000000")
        params[:image].rectangle(params[:subject_width] + coords[:bar_start], params[:top], params[:subject_width] + coords[:bar_end], params[:top] - height)

        # mark overflow
        if bin < 0
          x = params[:subject_width] + coords[:bar_start]
          y = params[:top]
          params[:image].line(x, y, x + coords[:bar_end] - coords[:bar_start], y - height)
        end
      end

      # overdue
      if workload[:overdue] && coords[:start]
        x = params[:subject_width] + coords[:start]
        y = params[:top] + height
        params[:image].fill('#FF0000')
        params[:image].stroke('none')
        params[:image].polygon(x-4, y, x, y-4, x+4, y)
      end
    end

    def pdf_workload(params, workload)
      coords = workload[:html_coords]
      value = workload[:value]
      height = 2

      if coords[:bar_start] && coords[:bar_end]
        colors = [[255, 0, 0], [255, 192, 0], [255, 255, 0], [192, 255, 0], [0, 255, 0], [0, 255, 0], [255, 0, 0]]
        bin = (value/25).floor
        if bin > 4
          color = colors[5]
        elsif bin < 0
          color = colors[6]
        else
          color = colors[bin]
        end

        # bar
        params[:pdf].SetY(params[:top]+1.5)
        params[:pdf].SetX(params[:subject_width] + coords[:bar_start])
        params[:pdf].SetFillColor(color[0], color[1], color[2])
        params[:pdf].SetDrawColor(0, 0, 0)
        params[:pdf].RDMCell(coords[:bar_end] - coords[:bar_start], height, "", 1, 0, "", 1)

        # mark overflow
        if bin < 0
          params[:pdf].SetY(params[:top]+1.5 + height / 2)
          params[:pdf].SetX(params[:subject_width] + coords[:bar_start])
          params[:pdf].SetFillColor(0, 0, 0)
          params[:pdf].SetDrawColor(-1)
          params[:pdf].RDMCell(coords[:bar_end] - coords[:bar_start], height / 2, "", 1, 0, "", 1)
        end
      end

      # overdue
      if workload[:overdue] && coords[:start]
        params[:pdf].SetY(params[:top] + 1.5 + height)
        params[:pdf].SetX(params[:subject_width] + coords[:bar_start])
        params[:pdf].SetFillColor(255, 0, 0)
        params[:pdf].SetDrawColor(-1)
        params[:pdf].RDMCell(coords[:bar_end] - coords[:bar_start], height / 2, "", 1, 0, "", 1)
      end
    end

    def html_task(params, coords, options={})
      output = ''
      # Renders the task bar, with progress and late
      if coords[:bar_start] && coords[:bar_end]
        output << "<div style='top:#{ params[:top] }px;left:#{ coords[:bar_start] }px;width:#{ coords[:bar_end] - coords[:bar_start] - 2}px;' class='#{options[:css]} task_todo'>&nbsp;</div>"

        if coords[:bar_late_end]
          output << "<div style='top:#{ params[:top] }px;left:#{ coords[:bar_start] }px;width:#{ coords[:bar_late_end] - coords[:bar_start] - 2}px;' class='#{options[:css]} task_late'>&nbsp;</div>"
        end
        if coords[:bar_progress_end]
          output << "<div style='top:#{ params[:top] }px;left:#{ coords[:bar_start] }px;width:#{ coords[:bar_progress_end] - coords[:bar_start] - 2}px;' class='#{options[:css]} task_done'>&nbsp;</div>"
        end
      end
      # Renders the markers
      if options[:markers]
        if coords[:start]
          output << "<div style='top:#{ params[:top] }px;left:#{ coords[:start] }px;width:15px;' class='#{options[:css]} marker starting'>&nbsp;</div>"
        end
        if coords[:end]
          output << "<div style='top:#{ params[:top] }px;left:#{ coords[:end] + params[:zoom] }px;width:15px;' class='#{options[:css]} marker ending'>&nbsp;</div>"
        end
      end
      # Renders the label on the right
      if options[:label]
        output << "<div style='top:#{ params[:top] }px;left:#{ (coords[:bar_end] || 0) + 8 }px;' class='#{options[:css]} label'>"
        output << options[:label]
        output << "</div>"
      end
      # Renders the tooltip
      if options[:issue] && coords[:bar_start] && coords[:bar_end]
        output << "<div class='tooltip' style='position: absolute;top:#{ params[:top] }px;left:#{ coords[:bar_start] }px;width:#{ coords[:bar_end] - coords[:bar_start] }px;height:12px;'>"
        output << '<span class="tip">'
        output << view.render_issue_tooltip(options[:issue])
        output << "</span></div>"
      end
      @lines << output
      output
    end
  end
end
