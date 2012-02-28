map.connect 'projects/:project_id/issues/:issue_id/time_entries/new', :action => 'edit', :controller => 'custom_timelog'

map.with_options :controller => 'custom_timelog' do |timelog|
    timelog.with_options :action => 'edit', :conditions => {:method => :get} do |time_edit|
      time_edit.connect 'issues/:issue_id/time_entries/new'
    end
end

