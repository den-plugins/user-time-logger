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
      budget_consumed = false

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

      if display_by_billing_model.eql?("fixed")
        budget_computation(@project.id)

        if (@project_budget - @actuals_to_date) < 0 && issue_is_billable
          budget_consumed = true
        end
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

          if total_hours <= 24 && user_is_member && accept_time_log && budget_consumed == false
            if @time_entry.save
              journal.save
              return call_mystic_process_billable_hours(@issue.id, params[:time_entry])
            end
          else
            flash[:error] = "Can't logged more than 24 hours." unless total_hours <= 24
            flash[:error] = "User is not a member of this project." unless user_is_member
            flash[:error] = "You are not allowed to log time to this task." unless accept_time_log
            flash[:error] = "Please log hours in a generic non-billable task. " unless budget_consumed == false
          end

        end
      end

    end

  private
  def custom_timelog_authorize(action = params[:action])
    allowed = User.current.allowed_to?({:controller => 'timelog', :action => action}, @project)
    allowed ? true : deny_access
  end

  def budget_computation(project_id)
      project = Project.find(project_id)
      bac_amount = project.project_contracts.all.sum(&:amount)
      contingency_amount = 0
      @actuals_to_date = 0
      @project_budget = 0

      pfrom, afrom, pto, ato = project.planned_start_date, project.actual_start_date, project.planned_end_date, project.actual_end_date
      to = (ato || pto)

      if pfrom && to
        team = project.members.project_team.all
        reporting_period = (Date.today-1.week).end_of_week
        forecast_range = get_weeks_range(pfrom, to)
        actual_range = get_weeks_range((afrom || pfrom), reporting_period)
        cost = project.monitored_cost(forecast_range, actual_range, team)
        actual_list = actual_range.collect {|r| r.first }
        cost.each do |k, v|
          if actual_list.include?(k.to_date)
            @actuals_to_date += v[:actual_cost]
          end
        end
        @project_budget = bac_amount + contingency_amount
      end
    end

    def display_by_billing_model
      if @project.billing_model
        if @project.billing_model.scan(/^(Fixed)/).flatten.present?
          "fixed"
        elsif @project.billing_model.scan(/^(T and M)/i).flatten.present?
          "billability"
        end
      end
    end

end
