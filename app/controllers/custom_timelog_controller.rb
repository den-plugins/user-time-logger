#*****************************************************************************
# controller that overrides some methods from timelogcontoller
#
#*****************************************************************************

class CustomTimelogController < TimelogController

  skip_before_filter :authorize, :only => [:edit, :destroy]
  before_filter :custom_timelog_authorize, :only => [:edit, :destroy]

  def edit
    render_403 and return if @time_entry && !@time_entry.editable_by?(User.current)
    @time_entry ||= TimeEntry.new(:project => @project, :issue => @issue, :user => User.current, :spent_on => Date.today)
    time_entry_clone = @time_entry.clone
    @time_entry.attributes = params[:time_entry]

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
        if @time_entry.save
          journal.save
          return call_mystic_process_billable_hours(@time_entry.issue_id, params[:time_entry])
        end
      end
    end
  end


  def report
    @available_criterias = { 'project' => {:sql => "#{TimeEntry.table_name}.project_id",
                                          :klass => Project,
                                          :label => :label_project},
                             'version' => {:sql => "#{Issue.table_name}.fixed_version_id",
                                          :klass => Version,
                                          :label => :label_version},
                             'category' => {:sql => "#{Issue.table_name}.category_id",
                                            :klass => IssueCategory,
                                            :label => :field_category},
                             'member' => {:sql => "#{Role.table_name}.name, #{User.table_name}.firstname, #{TimeEntry.table_name}.user_id",
                             # 'member' => {:sql => "#{TimeEntry.table_name}.user_id",
                                         :klass => User,
                                         :label => :label_member},
                             'tracker' => {:sql => "#{Issue.table_name}.tracker_id",
                                          :klass => Tracker,
                                          :label => :label_tracker},
                             'activity' => {:sql => "#{TimeEntry.table_name}.activity_id",
                                           :klass => Enumeration,
                                           :label => :label_activity},
                             'issue' => {:sql => "#{TimeEntry.table_name}.issue_id",
                                         :klass => Issue,
                                         :label => :label_issue}

                           }

    # Add list and boolean custom fields as available criterias
    custom_fields = (@project.nil? ? IssueCustomField.for_all : @project.all_issue_custom_fields)
    custom_fields.select {|cf| %w(list bool).include? cf.field_format }.each do |cf|
      @available_criterias["cf_#{cf.id}"] = {:sql => "(SELECT c.value FROM #{CustomValue.table_name} c WHERE c.custom_field_id = #{cf.id} AND c.customized_type = 'Issue' AND c.customized_id = #{Issue.table_name}.id)",
                                             :format => cf.field_format,
                                             :label => cf.name}
    end if @project

    # Add list and boolean time entry custom fields
    TimeEntryCustomField.find(:all).select {|cf| %w(list bool).include? cf.field_format }.each do |cf|
      @available_criterias["cf_#{cf.id}"] = {:sql => "(SELECT c.value FROM #{CustomValue.table_name} c WHERE c.custom_field_id = #{cf.id} AND c.customized_type = 'TimeEntry' AND c.customized_id = #{TimeEntry.table_name}.id)",
                                             :format => cf.field_format,
                                             :label => cf.name}
    end

    @criterias = params[:criterias] || []
    @criterias = @criterias.select{|criteria| @available_criterias.has_key? criteria}
    @criterias.uniq!
    @criterias = @criterias[0,3]
    @columns = (params[:columns] && %w(year month week day).include?(params[:columns])) ? params[:columns] : 'month'

    retrieve_date_range

    unless @criterias.empty?
      sql_select = @criterias.collect{|criteria| @available_criterias[criteria][:sql] + " AS " + criteria}.join(', ')
      sql_group_by = @criterias.collect{|criteria| @available_criterias[criteria][:sql]}.join(', ')

      sql = "SELECT #{sql_select}, tyear, tmonth, tweek, spent_on, SUM(hours) AS hours, #{Issue.table_name}.acctg_type AS accounting"
      sql << " FROM #{TimeEntry.table_name}"
      sql << " LEFT JOIN #{User.table_name} ON #{TimeEntry.table_name}.user_id = #{User.table_name}.id"
      sql << " LEFT JOIN #{Issue.table_name} ON #{TimeEntry.table_name}.issue_id = #{Issue.table_name}.id"
      sql << " LEFT JOIN #{Project.table_name} ON #{TimeEntry.table_name}.project_id = #{Project.table_name}.id"

      sql << " LEFT JOIN #{Member.table_name} ON #{User.table_name}.id = #{Member.table_name}.user_id and #{Member.table_name}.project_id = #{Project.table_name}.id"
      sql << " LEFT JOIN #{Role.table_name} ON #{Member.table_name}.role_id = #{Role.table_name}.id" if @criterias.include?('member')
      sql << " WHERE"
      sql << " (%s) AND" % @project.project_condition(Setting.display_subprojects_issues?) if @project
      sql << " (%s) AND" % Project.allowed_to_condition(User.current, :view_time_entries)
      sql << " (spent_on BETWEEN '%s' AND '%s')" % [ActiveRecord::Base.connection.quoted_date(@from.to_time), ActiveRecord::Base.connection.quoted_date(@to.to_time)]
      sql << " GROUP BY #{sql_group_by}, tyear, tmonth, tweek, spent_on, #{Issue.table_name}.acctg_type"
      sql << " ORDER BY roles.name asc, users.firstname asc" if @criterias.include?('member')
      @hours = ActiveRecord::Base.connection.select_all(sql)

      @hours.each do |row|
        case @columns
        when 'year'
          row['year'] = row['tyear']
        when 'month'
          row['month'] = "#{row['tyear']}-#{row['tmonth']}"
        when 'week'
          row['week'] = "#{row['tyear']}-#{row['tweek']}"
        when 'day'
          row['day'] = "#{row['spent_on']}"
        end
      end

      @details = []
      accounting = Enumeration.accounting_types

      if @criterias.include?('member')
        @subtotals = Hash.new
        @tx = 0
        accounting.each do |atyp|
          @hours.each do |hour|
            if hour["accounting"].to_i == atyp.id.to_i
              unless hour["name"].nil?
                if @subtotals[hour["name"] + ',' + "#{atyp.id}"].blank?
                  @subtotals[hour["name"] + ',' + "#{atyp.id}"] = hour["hours"].to_f
                else
                  @subtotals[hour["name"] + ',' + "#{atyp.id}"] += hour["hours"].to_f
                end
              end
              @tx += hour["hours"].to_f
            end
          end
        end
      end


      accounting.each do |atyp|
        hr = @hours.select {|h| h['accounting'].to_i == atyp.id.to_i}
        total = hr.inject(0) {|s,k| s= s + k['hours'].to_f}
        detail = {}
        detail[:atyp] = atyp
        detail[:total_hours] = total
        detail[:hour] = hr
        @details << detail

      end

      @periods = []
      # Date#at_beginning_of_ not supported in Rails 1.2.x
      date_from = @from.to_time
      # 100 columns max
      while date_from <= @to.to_time && @periods.length < 100
        case @columns
        when 'year'
          @periods << "#{date_from.year}"
          date_from = (date_from + 1.year).at_beginning_of_year
        when 'month'
          @periods << "#{date_from.year}-#{date_from.month}"
          date_from = (date_from + 1.month).at_beginning_of_month
        when 'week'
          @periods << "#{date_from.year}-#{date_from.to_date.cweek}"
          date_from = (date_from + 7.day).at_beginning_of_week
        when 'day'
          @periods << "#{date_from.to_date}"
          date_from = date_from + 1.day
        end
      end
    end

    respond_to do |format|
      format.html { render :layout => !request.xhr? }
      format.csv  { send_data(report_to_csv(@criterias, @periods, @hours).read, :type => 'text/csv; header=present', :filename => 'timelog.csv') }
    end
  end

  private
  def custom_timelog_authorize(action = params[:action])
    allowed = User.current.allowed_to?({:controller => 'timelog', :action => action}, @project)
    allowed ? true : deny_access
  end
end
