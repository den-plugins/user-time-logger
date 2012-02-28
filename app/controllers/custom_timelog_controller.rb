#*****************************************************************************
# controller that overrides some methods from timelogcontoller
#
#*****************************************************************************

class CustomTimelogController < TimelogController

  skip_before_filter :authorize, :only => [:edit, :destroy]
  before_filter :custom_timelog_authorize, :only => [:edit, :destroy]

    def edit
    total_hours = 0.0
    user_is_member = false
    rate = 0
    issue_is_billable = false
    accept_time_log = false

    render_403 and return if @time_entry && !@time_entry.editable_by?(User.current)
    @time_entry ||= TimeEntry.new(:project => @project, :issue => @issue, :user => User.current, :spent_on => Date.today)
    time_entry_clone = @time_entry.clone
    @time_entry.attributes = params[:time_entry]

    @total_entries = User.find(@time_entry.user_id).time_entries.find(:all, :conditions => "spent_on = '#{@time_entry.spent_on}'")
    @total_entries.each do |v|
      total_hours += v.hours
    end

    Project.find(@project.id).members.project_team.each do |m|
      if @time_entry.user_id == m.user_id
        user_is_member = true
        rate = m.internal_rate ? m.internal_rate : 0
      end
    end

    issue_is_billable = true if Issue.find(@issue.id).acctg_type == Enumeration.find_by_name('Billable').id

    if rate
    accept_time_log = true if (issue_is_billable && rate > 0) || (!issue_is_billable && rate == 0)  ||
        (!issue_is_billable && rate > 0)
    end

      TimeEntry.transaction do
        if request.post?
          total_time_entry = TimeEntry.sum(:hours, :conditions => "issue_id = #{@time_entry.issue.id}")
          journal = @time_entry.init_journal(User.current)
          journal.details << JournalDetail.new(:property => 'timelog', :prop_key => 'hours', :old_value => (time_entry_clone.hours if time_entry_clone.hours != @time_entry.hours), :value => @time_entry.hours)
          journal.details << JournalDetail.new(:property => 'timelog', :prop_key => 'activity_id', :old_value => (time_entry_clone.activity_id if !time_entry_clone.activity_id.eql?(@time_entry.activity_id)), :value => @time_entry.activity_id)
          journal.details << JournalDetail.new(:property => 'timelog', :prop_key => 'spent_on', :old_value => (time_entry_clone.spent_on if !time_entry_clone.spent_on.eql?(@time_entry.spent_on)), :value => @time_entry.spent_on)
          if !@time_entry.issue.estimated_hours.nil?
            remaining_estimate = @time_entry.issue.estimated_hours - total_time_entry
            journal.details << JournalDetail.new(:property => 'timelog', :prop_key => 'remaining_estimate', :value => remaining_estimate >= 0 ? remaining_estimate : 0)
          end
          unless @time_entry.hours.nil?
            total_hours += @time_entry.hours
          end

          if total_hours <= 24 && user_is_member && accept_time_log
            if @time_entry.save
              journal.save
              return call_mystic_process_billable_hours(@issue.id, params[:time_entry])
            end
          else
            flash[:error] = "Can't logged more than 24 hours." unless total_hours <= 24
            flash[:error] = "User is not a member of this project." unless user_is_member
            flash[:error] = "You are not allowed to log time to this task." unless accept_time_log
          end

        end
      end

    end

  private
  def custom_timelog_authorize(action = params[:action])
    allowed = User.current.allowed_to?({:controller => 'timelog', :action => action}, @project)
    allowed ? true : deny_access
  end

end
