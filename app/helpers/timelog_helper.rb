module TimelogHelper
  include ApplicationHelper

  def custom_render_timelog_breadcrumb
    links = []
    links << link_to(h(@project), {:project_id => @project, :issue_id => nil}) if @project
    links << link_to_issue(@issue) if @issue
    breadcrumb links
  end

end
