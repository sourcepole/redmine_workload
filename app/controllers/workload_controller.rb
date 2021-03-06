class WorkloadController < ApplicationController
  unloadable

  before_filter :require_login, :find_optional_project

  rescue_from Query::StatementInvalid, :with => :query_statement_invalid

  helper :issues
  helper :projects
  helper :queries
  include QueriesHelper
  helper :sort
  include SortHelper
  include Redmine::Export::PDF

  def show
    @workload = Workload::Workload.new(params)
    @workload.project = @project
    retrieve_query
    @query.group_by = nil
    @workload.query = @query if @query.valid?

    basename = (@project ? "#{@project.identifier}-" : '') + 'workload'

    respond_to do |format|
      format.html { render :action => "show", :layout => !request.xhr? }
      format.png  { send_data(@workload.to_image, :disposition => 'inline', :type => 'image/png', :filename => "#{basename}.png") } if @workload.respond_to?('to_image')
      format.pdf  { send_data(@workload.to_pdf, :type => 'application/pdf', :filename => "#{basename}.pdf") }
    end
  end
end
