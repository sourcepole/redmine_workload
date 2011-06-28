class WorkloadController < ApplicationController
  unloadable

  rescue_from Query::StatementInvalid, :with => :query_statement_invalid

  helper :issues
  helper :projects
  helper :queries
  include QueriesHelper
  helper :sort
  include SortHelper
  include Redmine::Export::PDF
  include Workload

  def show
    @workload = Workload::Workload.new(params)
    retrieve_query
    @query.group_by = nil
    @workload.query = @query if @query.valid?

    basename = 'workload'

    respond_to do |format|
      format.html { render :action => "show", :layout => !request.xhr? }
      format.png  { send_data(@workload.to_image, :disposition => 'inline', :type => 'image/png', :filename => "#{basename}.png") } if @workload.respond_to?('to_image')
      format.pdf  { send_data(@workload.to_pdf, :type => 'application/pdf', :filename => "#{basename}.pdf") }
    end
  end
end
