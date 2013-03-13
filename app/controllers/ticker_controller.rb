# 
# ---------------------------------------------------------------------------
#  Copyright 2007,2008 CompanyNameHere
#  All Rights Reserved.
# 
#  This is UNPUBLISHED PROPRIETARY SOURCE CODE of CompanyNameHere.;
#  the contents of this file may not be disclosed to third parties, copied or
#  duplicated in any form, in whole or in part, without the prior written
#  permission of CompanyNameHere.
# ---------------------------------------------------------------------------
 
class TickerController < ApplicationController
  unloadable
  
  include FaceboxRender
  helper :scrums
  helper :timelog
  helper :ticker
  helper :sort
  include SortHelper
  include TimelogHelper
  include TickerHelper
  helper_method :leave_entries_to_csv
  helper_method :display_time_entries_errors_nicely
  
  # show the ticker on the homepage
  def show
     render :layout => false
  end
  
  # save the time logged by the user
  def create
    render_403 and return if @time_entry && !@time_entry.editable_by?(User.current)
    user = User.current
    # TODO: move this to a  helper method that would be available to any views would like to use
    @assigned_issues = Issue.find(:all, 
                                  :conditions => ["assigned_to_id=? AND #{IssueStatus.table_name}.is_closed=? AND #{Project.table_name}.status=#{Project::STATUS_ACTIVE}", user.id, false], 
                                  :include => [ :status, :project, :tracker, :priority ], 
                                  :order => "#{Enumeration.table_name}.position DESC, #{Issue.table_name}.updated_on DESC").map { |i| [i.subject, i.id] }
        
    if request.post?
      issue = Issue.find(params[:time_entry][:issue_id])
      project = issue.project
      
      @time_entry = TimeEntry.new(:project => project, :issue => issue, :user => User.current)
      @time_entry.init_journal(User.current, @time_entry.comments)
      @time_entry.attributes = params[:time_entry]
      if !@time_entry.save
        render :update do |page|
          page.replace_html 'modal_container', :partial =>  'log_time'
          page<< "mbox = iBox.getElementSize($('modal_container'));"
          page<< "iBox.resizeObjectToScreen($('ibox_content'), mbox.width, mbox.height, false);"
          page<< "iBox.resizeObjectToScreen($('ibox_wrapper'), mbox.width+5, mbox.height+5, false);"
          page<< "iBox.center($('ibox_wrapper'));"
        end
        return
      end
      render :update do |page|
        page<< "iBox.hide();"
        page.redirect_to(:controller => 'my', :action => 'page')
      end
    else
      render :layout => false
    end
  end
  
  # TODO: 1.merge this for the create action
  #       2.we have to tidy up the create action
  def log_time_from_assigned_issues
    errors = []
    if params[:ids]
      params[:ids].each do |k,v|
        project = Issue.find(k).project
        if project.lock_time_logging && params[:time_entries][k][:spent_on].to_date <= project.lock_time_logging
          errors << "* #{project.name} until #{project.lock_time_logging}<br>"
        end
      end
      unless errors.blank?
        errors.insert(0, "Time Logging is Prohibited for the ff :<br>")
      end
    end

    if errors.blank?
      saved_time_entries,unsaved_time_entries = TimeEntry.save_time_entries(User.current, params[:ids]||=[], params[:time_entries]) 
      if unsaved_time_entries.length > 0
        errors << display_time_entries_errors_nicely(unsaved_time_entries)
      end
    end
    flash[:error] = errors.uniq unless errors.blank?
    redirect_to(:controller => 'my', :action => 'page')
  end
  
  def my_timelogs
    sort_init 'spent_on', 'desc'
    sort_update ['spent_on']
    
    conditions = ['user_id = ?', User.current.id]
    TimeEntry.visible_by(User.current) do
      respond_to do |format|
        format.html {
          # Paginate results
          @entry_count = TimeEntry.count(:include => :project, :conditions => conditions)
          @entry_pages = Paginator.new self, @entry_count, per_page_option, params['page']
          @entries = TimeEntry.find(:all, 
                                    :include => [:project, :activity, :user, {:issue => :tracker}],
                                    :conditions => conditions,
                                    :order => sort_clause,
                                    :limit  =>  @entry_pages.items_per_page,
                                    :offset =>  @entry_pages.current.offset)
          @total_hours = TimeEntry.sum(:hours, :include => :project, :conditions => conditions).to_f

          render :layout => !request.xhr?
        }
        format.atom {
          entries = TimeEntry.find(:all,
                                   :include => [:project, :activity, :user, {:issue => :tracker}],
                                   :conditions => conditions,
                                   :order => "#{TimeEntry.table_name}.created_on DESC",
                                   :limit => Setting.feeds_limit.to_i)
          render_feed(entries, :title => l(:label_spent_time))
        }
        format.csv {
          # Export all entries
          @entries = TimeEntry.find(:all, 
                                    :include => [:project, :activity, :user, {:issue => [:tracker, :assigned_to, :priority]}],
                                    :conditions => conditions,
                                    :order => sort_clause)
          send_data(entries_to_csv(@entries).read, :type => 'text/csv; header=present', :filename => 'timelog.csv')
        }
      end
    end
  end

  def recurring_issues
    #get category id of Project Generic Tasks and  Exist Services Activities
    categories = User.current.projects.map do |project|
      project.issue_categories.find(:all,
                                    :conditions=>["name like ? OR name like ?",'Project Generic Tasks','Exist Services Activities'])
    end
    @issue_count = Issue.count(:all,
                               :conditions=>["category_id IN (#{categories.flatten.map(&:id).join(',')}) "])
    @issue_pages = Paginator.new self, @issue_count, per_page_option, params['page']
    @issues = Issue.visible.find(:all,
                         :conditions => ["category_id IN (#{categories.flatten.map(&:id).join(',')}) "],
                         :order      => "project_id DESC, category_id DESC",
                         :limit      =>  @issue_pages.items_per_page,
                         :offset     =>  @issue_pages.current.offset)
    if request.xhr?
      render :partial=>"recurring_issues"
    else
      render :action=>"recurring_issues"
    end
  end
  
  def update_recurring_issues
    @user = User.current
    categorized_issues(params[:category])
    render :update do |page|
      page.replace_html 'recurring_issues', :partial => 'issues/list_recurring_issues', :locals => {:issues =>@issues, :category => params[:category]}
    end
  end

  def update_time_entries
    projects = retrieve_projects
    retrieve_date_range(params[:period_type],params[:period])
    conditions = ["#{TimeEntry.table_name}.spent_on BETWEEN ? AND ?", @from, @to]
    sort_by = "#{TimeEntry.table_name}.spent_on DESC, #{Project.table_name}.name ASC, #{Tracker.table_name}.position ASC, #{Issue.table_name}.id ASC"
#    @entries_count = TimeEntry.count(:all,
#                                     :conditions => conditions)
#    @entries_pages = Paginator.new self, @entries_count, per_page_option, params['page']
    
    entries = TimeEntry.find(:all,
                             :conditions => conditions,
		             :include    => [:activity, :project, {:issue => [:tracker, :status, :accounting]}],
		             :order      => sort_by)
#		,
#                             :limit      => @entries_pages.items_per_page,
#                             :offset     => @entries_pages.current.offset)
    entries.delete_if{|u|!subordinate?(u,projects)} if !User.current.admin?
    
    entries_non_bill = []
    entries_bill = []
    entries.each do |entry|  
      if entry.issue.accounting.name.downcase.eql?("billable")
        entries_bill << entry
      else
        entries_non_bill << entry
      end
    end
    
    respond_to do |format|
      format.html { 
        if request.post?
          render :partial => "my/blocks/time_entries_details", :locals => {:entries => entries_bill, :entries_non_bill => entries_non_bill, :projects => projects, :option => params[:option], :view => params[:view] }
        else
          render :update do |page|
            page.replace 'time_entries_details', :partial => "my/blocks/time_entries_details", :locals => {:entries => entries_bill, :entries_non_bill => entries_non_bill, :projects => projects, :option => params[:option],  :view => params[:view]}
          end
        end
      }
      format.csv { send_data(entries_to_csv(entries_bill+entries_non_bill).read, :type => 'text/csv; header=present', :filename => 'time_entries_report.csv') }
    end
  end
  

  def update_time_entries_simple
   	@billing_model = CustomField.find_by_name('Billing Model')

  	if @billing_model
	  	@billing_model_values = [["All", "0"]]
	  	@billing_model.possible_values.each do |v|
	  		@billing_model_values << v
	  	end
	  end

   	@project_type = CustomField.find_by_name('Project Type')

  	if @project_type
	  	@project_type_values = [["All", "0"]]
	  	@project_type.possible_values.each do |line|
	  		@project_type_values << line
	  	end
	  end	  

    retrieve_date_range(params[:period_type],params[:period])
    @columns = (params[:columns] && %w(year month week day).include?(params[:columns])) ? params[:columns] : 'month'
    @query = (params[:query].blank?)? "user" : params[:query]
    @disable_acctype_options = (@query == "user")? true : false
    @eng_only, eng_only = (params[:eng_only] == "1" || params[:right].blank? )? [true, "is_engineering = true"] : [false, nil] 
    @for_acctg = (params[:for_acctg] == "1" )? true : false
    @show_only = (params[:show_only].blank?)? "both" : params[:show_only]
    @tall ||= []

    @selected_acctype = ((params[:acctype].blank?)? "" : params[:acctype]).to_i
    @acctype_options = [["All", ""]]
    Enumeration.accounting_types.each do |at|
      @acctype_options << [at.name, at.id]
    end
    
    user_select = "id, firstname, lastname, status"
    user_order = "firstname asc, lastname asc"
    project_select = "id, name"
    project_order = "name asc"
    
    @billing = params[:billing_model]
    @project_billing_ids = []
    billings = CustomValue.find_all_by_value(@billing)
    billings.each do |x|
    	@project_billing_ids << x.customized_id
    end if billings

    @projtype = params[:project_type]
    @project_type_ids = []
    projtypes = CustomValue.find_all_by_value(@projtype)
    projtypes.each do |x|
    	@project_type_ids << x.customized_id
    end if projtypes

    if @query == "user"
      available_user_conditions = []
      available_user_conditions << "\"users\".\"status\" = 1"
      available_user_conditions << eng_only
      available_user_conditions << ( (params[:selectednames].blank?)? nil : "id not in (#{params[:selectednames].join(',')})")
      available_user_conditions = available_user_conditions.compact.join(" and ")
      @available_users = User.all(:select => user_select,
                                  :conditions => available_user_conditions,
                                  :order => user_order)
      
      selected_user_conditions = []
      selected_user_conditions << "\"users\".\"status\" = 1"
      selected_user_conditions << eng_only
      selected_user_conditions << ( (params[:selectednames].blank?)? "id is null" : "id in (#{params[:selectednames].join(',')})")
      selected_user_conditions = selected_user_conditions.compact.join(" and ")
      @selected_users = User.all(:select => user_select,
                                  :conditions => selected_user_conditions,
                                  :include => [:memberships],
                                  :order => user_order)
      @available_projects = Project.active.all(:select => project_select,
                                        :order => project_order )
      @selected_projects = []
    else


    	@project_billing_ids = [0] if @project_billing_ids.empty? and @billing != 0 and !@billing.nil?
    	@project_type_ids = [0] if @project_type_ids.empty? and @projtype != 0 and @projtype != nil
      available_project_conditions = []
      available_project_conditions << ( (@selected_acctype == 0)? nil : "\"projects\".\"acctg_type\" = #{params[:acctype]}")
      available_project_conditions << ( (params[:selectedprojects].blank?)? nil : "id not in (#{params[:selectedprojects].join(',')})")
			available_project_conditions << ("id in (#{@project_billing_ids.join(',')})") if !@project_billing_ids.empty? and @billing != "0" and !@billing.nil?
			available_project_conditions << ("id in (#{@project_type_ids.join(',')})") if !@project_type_ids.empty? and @projtype != "0" and @projtype != ""
      available_project_conditions = available_project_conditions.compact.join(" and ")
      #available_project_conditions = ( (params[:selectedprojects].blank?)? "" : "id not in (#{params[:selectedprojects].join(',')})")

      @available_projects = Project.active.all(:select => project_select,
                                        :conditions => available_project_conditions,
                                        :order => project_order)
      selected_project_conditions = ( (params[:selectedprojects].blank?)? "id is null" : "id in (#{params[:selectedprojects].join(',')})")
      @selected_projects = Project.active.all(:select => project_select,
                                       :conditions => selected_project_conditions,
                                       :order => project_order)
      selected_user_conditions = []
      selected_user_conditions << "\"users\".\"status\" = 1"
      selected_user_conditions << eng_only
      selected_user_conditions << ( (@selected_projects.size > 0)? "users.id in ( select m.user_id from members as m where m.project_id in( #{@selected_projects.collect(&:id).join(',')} ) )" : "id is null")
      selected_user_conditions = selected_user_conditions.compact.join(" and ")
      @selected_users = User.all( :select => user_select,
                                   :conditions => selected_user_conditions,
                                   :include => [:projects, {:memberships, :role }],
                                   :order => user_order)
                                   
      available_user_conditions = []
      available_user_conditions << "\"users\".\"status\" = 1"
      available_user_conditions << eng_only
      available_user_conditions << ((@selected_users.size > 0)? "id not in (#{@selected_users.collect(&:id).join(',')})" : nil )
      available_user_conditions = available_user_conditions.compact.join(" and ")
      @available_users = User.all(:select => user_select,
                                  :conditions => available_user_conditions,
                                  :order => user_order)
    end
    
    if params[:eng_only_csv]
      @selected_users = User.all( :select => "id, firstname, lastname", 
                        :conditions => "is_engineering = true and status = 1",
                        :order      => "firstname asc, lastname asc")
    end
    
    user_list = (@selected_users.size > 0)? "time_entries.user_id in (#{@selected_users.collect(&:id).join(',')}) and" : ""
    project_list = (@selected_projects.size > 0)? "time_entries.project_id in (#{@selected_projects.collect(&:id).join(',')}) and" : ""   
    bounded_time_entries_billable = TimeEntry.find(:all, 
                                :conditions => ["#{user_list} #{project_list} spent_on between ? and ? and issues.acctg_type = (select id from enumerations where name = 'Billable')",
                                @from, @to],
                                :include => [:project],
                                :joins => [:issue],
                                :order => "projects.name asc" )
    bounded_time_entries_billable.each{|v| v.billable = true }
    bounded_time_entries_non_billable = TimeEntry.find(:all, 
                                :conditions => ["#{user_list} #{project_list} spent_on between ? and ? and issues.acctg_type = (select id from enumerations where name = 'Non-billable')",
                                @from, @to],
                                :include => [:project],
                                :joins => [:issue],
                                :order => "projects.name asc" )
    bounded_time_entries_non_billable.each{|v| v.billable = false }
    time_entries = TimeEntry.find(:all, 
                                :conditions => ["#{user_list} spent_on between ? and ?", 
                                @from, @to] )                            
                               
    ######################################
    # th = total hours regardless of selected projects
    # tth = total hours on selected projects
    # tbh = total billable hours on selected projects
    # tnbh = total non-billable hours on selected projects
    ######################################
    @th = time_entries.collect(&:hours).compact.sum
    @tbh = bounded_time_entries_billable.collect(&:hours).compact.sum
    @tnbh = bounded_time_entries_non_billable.collect(&:hours).compact.sum
    @thos = (@tbh + @tnbh)
    @summary = []
    
    if @for_acctg
      @total_internal_rates = []
      @total_computed_internal_rates = []
      @total_sow_rates = []
      @total_computed_sow_rates = []
    end
    @selected_users.each do |usr|
      if usr.class.to_s == "User"
        b = bounded_time_entries_billable.select{|v| v.user_id == usr.id }
        nb = bounded_time_entries_non_billable.select{|v| v.user_id == usr.id }
        x = Hash.new
        
        if @for_acctg
          internal_rate = []
          computed_internal_rate = []
          sow_rate = []
          computed_sow_rate = []
        end
        if @for_acctg
          usr.memberships.each do |r|
              hours = b.select{|v| v.project_id == r.project_id}.collect(&:hours).compact.sum
              inthours = hours*r.internal_rate.to_f
              sowhours = hours*r.sow_rate.to_f
              if inthours > 0  
                internal_rate << sprintf("%.2f", r.internal_rate)
                computed_internal_rate << sprintf("%.2f", inthours)
              end
              if sowhours > 0
                sow_rate << sprintf("%.2f", r.sow_rate)
                computed_sow_rate << sprintf("%.2f", sowhours)
              end
          end
          @total_internal_rates << internal_rate.inject(0) { |s,v| s += v.to_f }
          @total_computed_internal_rates << computed_internal_rate.inject(0) { |s,v| s += v.to_f }
          @total_sow_rates << sow_rate.inject(0) { |s,v| s += v.to_f }
          @total_computed_sow_rates << computed_sow_rate.inject(0) { |s,v| s += v.to_f }
        end
        
        jt = []
        if @query == "user"
          @selected_projects.each do |project|
            usr.memberships.each do |membership|
              if membership.project_id == project.id 
                jt << membership.role.name
              end
            end
          end
        else
          @selected_projects.each do |project|
            usr.memberships.each do |membership|
              if membership.project_id == project.id 
                jt << membership.role.name
              end
            end
          end
        end
        jt = jt.uniq.compact.join(' / ')
        
        x[:user_id] = usr.id
        x[:name] = usr.name
        x[:job_title] = jt 
        x[:entries] = b + nb
        x[:total_hours] = time_entries.select{|v| v.user_id == usr.id }.collect(&:hours).compact.sum
        x[:billable_hours] = b.collect(&:hours).compact.sum
        x[:non_billable_hours] = nb.collect(&:hours).compact.sum
        x[:total_hours_on_selected] = x[:billable_hours] + x[:non_billable_hours]
        if @for_acctg
          x[:internal_rate] = internal_rate.join(" / ")
          x[:computed_internal_rate] = computed_internal_rate.join(" / ")
          x[:sow_rate] = sow_rate.join(" / ")
          x[:computed_sow_rate] = computed_sow_rate.join(" / ")
        end
        @summary.push(x)
      end
    end
    
    if @for_acctg
      @total_internal_rates = @total_internal_rates.inject(0) { |s,v| s += v }
      @total_computed_internal_rates = @total_computed_internal_rates.inject(0) { |s,v| s += v }
      @total_sow_rates = @total_sow_rates.inject(0) { |s,v| s += v }
      @total_computed_sow_rates = @total_computed_sow_rates.inject(0) { |s,v| s += v }
      
      @total_internal_rates = 0 if @total_internal_rates.blank?
      @total_computed_internal_rates = 0 if @total_computed_internal_rates.blank?
      @total_sow_rates = 0 if @total_sow_rates.blank?
      @total_computed_sow_rates = 0 if @total_computed_sow_rates.blank?
    end
    
    @summary = @summary.sort_by{|c| "#{c[:job_title]}#{c[:name]}" }
    
    respond_to do |format|
      format.html { 
        if request.post?
          render :partial => "my/blocks/time_entries_details_simple", :locals => {:option => params[:option], :view => params[:view] }
        else
          render :update do |page|
            page.replace 'time_entries_details', :partial => "my/blocks/time_entries_details_simple", :locals => {:option => params[:option], :view => params[:view]}
          end
        end
      }
      format.csv { send_data(entries_to_csv_simple(@summary).read, :type => 'text/csv; header=present', :filename => 'time_entries_report_simple.csv') }
    end
    
  end
  
  def user_timelogs
    @columns = params[:type]
    @show_only = "both"
    @from = Date.parse(params[:from])
    @to = Date.parse(params[:to])
    @user = User.find(params[:user_id])
    @projects = @user.projects
    #@entries = TimeEntry.find(:all,
    #                          :conditions => ["user_id = ? and spent_on between ? and ?", @user.id, @from, @to] )
    @entries_billable = TimeEntry.find(:all,
                                  :conditions => ["user_id = ? and spent_on between ? and ? and issues.acctg_type = (select id from enumerations where name = 'Billable') ",
                                   @user.id, @from, @to],
                                  :joins => [:issue] )
    @entries_non_billable = TimeEntry.find(:all,
                                  :conditions => ["user_id = ? and spent_on between ? and ? and issues.acctg_type = (select id from enumerations where name = 'Non-billable') ",
                                   @user.id, @from, @to],
                                  :joins => [:issue] )
    @summary = []
    @tall ||= []

    current_proj = Project.find params[:project_id]
    @projects.each do |prj|

      x = Hash.new
      x[:admin] = prj.is_admin_project? && current_proj.parent.children.include?(prj) ? true : false
      x[:project_id] = prj.id
      x[:name] = prj.name
      x[:job_title] = @user.memberships.select{|e| e.project_id == prj.id }[0].role.name
      
      billable_entries = @entries_billable.select{|e| e.project_id == prj.id }
      non_billable_entries = @entries_non_billable.select{|e| e.project_id == prj.id }
      
      x[:entries] = billable_entries + non_billable_entries
      
      x[:billable_hours] = billable_entries.collect(&:hours).compact.sum
      x[:non_billable_hours] = non_billable_entries.collect(&:hours).compact.sum
      x[:total_hours] = x[:billable_hours] + x[:non_billable_hours]
      @summary.push(x)
    end
    # @entries.inject(0){|sum, hash| sum+hash[:hours]}
   
    @tbh = @entries_billable.collect(&:hours).compact.sum
    @tnbh = @entries_non_billable.collect(&:hours).compact.sum
    @th = @tbh + @tnbh

    respond_to do |format|
      format.html
      format.js { render_to_facebox :layout => false }
    end
  end
  
  def update_leave_entries
    projects = retrieve_projects
    retrieve_date_range(params[:leave_period_type],params[:leave_period])
    cond = ["#{LeaveEntries.table_name}.spent_on >= ? AND
             #{LeaveEntries.table_name}.spent_on <= ? ", @from, @to]
#    @leaves_count = LeaveEntries.count(:all, 
#                                       :conditions => cond )
#    @leaves_pages = Paginator.new self, @leaves_count, per_page_option, params['page']
    leaves = LeaveEntries.find(:all,
                               :conditions => cond,
#                               :limit      => @leaves_pages.items_per_page,
#                               :offset     => @leaves_pages.current.offset,
                               :include    => :user)
    if params[:option].eql?("")
      leaves.delete_if{|u| u.user.members.empty?}
#      @leaves_count = leaves.size
#      @leaves_pages = Paginator.new self, @leaves_count, per_page_option, params['page']
    end
    
    leaves.delete_if{|u|!subordinate?(u,projects)} if !User.current.admin?
    
        
    respond_to do |format|
      format.html do
    if request.post?
      render :partial => "my/blocks/leave_entries_details#{params[:option]}", :locals => {:leaves => leaves, :projects => projects}
    else
      render :update do |page|
        page.replace 'leave_entries_details', :partial => "my/blocks/leave_entries_details#{params[:option]}", 
                                                        :locals => {:leaves => leaves, :projects => projects}
      end
    end
        
      end
      format.csv { send_data(leave_entries_to_csv(leaves, projects, params[:option]).read, :type => 'text/csv; header=present', :filename => 'leave_entries.csv')}
    end
  end
  
  #TODO: refactor this with the list of recurring issues
  def categorized_issues(issue_category)
    categories = User.current.projects.map do |project|
      project.issue_categories.find(:all,
                                    :conditions=>["name ilike ?", "#{issue_category}"])
    end
    pids = User.current.memberships.select {|m| m.role.allowed_to?(:log_time)}.collect {|m| m.project_id}
    @issues = Issue.find(:all,
                         :conditions => ["category_id IN (#{categories.flatten.map(&:id).join(',')}) AND project_id IN (?)", pids],
                         :order      => "project_id DESC, category_id DESC, updated_on DESC")
  end
  
  private
    
  # this will be available int he controller and the view
  # made it private so that it will not be available in the url
  # this is a helper method that will display the error messages on the time entries on the modified assigned_issues_to_me
  def display_time_entries_errors_nicely(unsaved_time_entries=[])
    full_error_msg = []
    unsaved_time_entries.each do |time_entry|
      count = time_entry.errors.count
      class_name = "#{time_entry.issue} [TimeEntry]"
      header_message = "#{count} error(s) prohibited in #{class_name} from being saved"
      error_messages = time_entry.errors.full_messages.map {|msg| "<li> #{msg}</li>" }.join

      contents = ''
      contents << "<p> #{header_message} </p>" unless header_message.blank?
      contents << "<ul> #{error_messages} </ul>"
      full_error_msg<< "<div> #{contents} </div>"
    end
    return (full_error_msg.empty? ? nil: full_error_msg)
  end
    
  # Retrieves the date range based on predefined ranges or specific from/to param dates
  def retrieve_date_range(period_type,period)
    @free_period = false
    @from, @to = nil, nil

    if period_type == '1' || (period_type.nil? && !period_type.nil?)
      case period.to_s
      when 'today'
        @from = @to = Date.today
      when 'yesterday'
        @from = @to = Date.today - 1
      when 'current_week'
        @from = Date.today - (Date.today.cwday - 1)%7
        @to = @from + 6
      when 'last_week'
        @from = Date.today - 7 - (Date.today.cwday - 1)%7
        @to = @from + 6
      when '7_days'
        @from = Date.today - 7
        @to = Date.today
      when 'current_month'
         current_month
      when 'last_month'
        @from = Date.civil(Date.today.year, Date.today.month, 1) << 1
        @to = (@from >> 1) - 1
      when '30_days'
        @from = Date.today - 30
        @to = Date.today
      when 'current_year'
        @from = Date.civil(Date.today.year, 1, 1)
        @to = Date.civil(Date.today.year, 12, 31)
      end
    elsif period_type == '2' || (period_type.nil? && (!params[:from].nil? || !params[:to].nil?))
      begin; @from = params[:from].to_s.to_date unless params[:from].blank?; rescue; end
      begin; @to = params[:to].to_s.to_date unless params[:to].blank?; rescue; end
      begin; @from = params[:leaves_from].to_s.to_date unless params[:leaves_from].blank?; rescue; end
      begin; @to = params[:leaves_to].to_s.to_date unless params[:leaves_to].blank?; rescue; end
      @free_period = true
    else
      # default
      current_month
    end
    
    @from, @to = @to, @from if @from && @to && @from > @to
    @from ||= (TimeEntry.minimum(:spent_on, :include => :project, :conditions => Project.allowed_to_condition(User.current, :view_time_entries)) || Date.today) - 1
    @to   ||= (TimeEntry.maximum(:spent_on, :include => :project, :conditions => Project.allowed_to_condition(User.current, :view_time_entries)) || Date.today)
  end

  def current_month
    @from = Date.civil(Date.today.year, Date.today.month, 1)
    @to = (@from >> 1) - 1
  end
  
  def get_selected_user
    if !params[:user].nil? || !params[:user].eql?("")
      @user = User.find(params[:user])
    else
      @user = User.current
    end
  end

  def retrieve_projects
    if User.current.admin?
      return Project.find(:all,
                          :conditions => "#{Project.table_name}.status = #{Project::STATUS_ACTIVE}",
                          :include    => [:members, :issues],
                          :order      => "#{Project.table_name}.id DESC")
    else
      return User.current.manager_role_for_project(User.current.projects)
    end
  end
  
  def subordinate?(entry,projects)
    projects.each do |proj|
      if entry.class.eql?(TimeEntry) && entry.issue.project.eql?(Project.find_by_name(proj.name))
        return true
      elsif entry.class.eql?(LeaveEntries)
        entry.user.projects.each do |p| 
          if p.eql?(Project.find_by_name(proj.name))
            return true
          end
        end
      end
    end
    return false
  end
end
