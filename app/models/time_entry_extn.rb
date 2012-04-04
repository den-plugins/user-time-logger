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
 
# This is showing a more traditional way of mixin a function to a persistence module
# placing it under the /lib folder and require it on the init.rb

module TimeEntryExtn    
  
  def self.included(base)
    base.extend ClassMethods
  end
  
  # ----------------------------------------------------------------------------
  # Class Methods
  # ----------------------------------------------------------------------------
  module ClassMethods
   
    # this will save multiple time entries given the issue_ids and the time entries
    # issue_ids = [1,2,6]
    # time_entries = { issue_id => { :hours => 2 , :activity_id => 1} ,  }
    # and will return [saved_time_entries,unsaved_time_entries]
    def save_time_entries(user, issue_ids=[], time_entries={})
      saved_time_entries = []
      unsaved_time_entries = []

      default_attribute = { :comments => 'Logged spent time.',
                            :user => user}
      issue_ids.each do |id|
        time_entry = nil
        issue = Issue.find(id, :include => :project)
        project = issue.project
        time_entry = TimeEntry.new#TimeEntry.new(default_attribute.merge(time_entries[id]))
        time_entry.issue = issue
        journal = time_entry.init_journal(user)
        time_entry.project = project
        time_entry.spent_on = time_entries[id][:spent_on].to_date
        time_entry.attributes=(default_attribute.merge(time_entries[id]))
        activ = Enumeration.activities.select{|a|a.id == time_entries[id][:activity_id].to_i}
        time_entry.comments = time_entries[id][:comments].empty? ? (activ.empty? ? "Logged spent time." : "Logged spent time. Doing #{activ.first.name} on #{issue.subject}.") : time_entries[id][:comments]

        if time_entry.save
          total_time_entry = TimeEntry.sum(:hours, :conditions => "issue_id = #{time_entry.issue.id}")
          if !time_entry.issue.estimated_hours.nil?
            remaining_estimate = time_entry.issue.estimated_hours - total_time_entry
            journal.details << JournalDetail.new(:property => 'timelog', :prop_key => 'remaining_estimate', :value => remaining_estimate >= 0 ? remaining_estimate : 0)
          end
          journal.save
          saved_time_entries << time_entry
        else
          unsaved_time_entries << time_entry
        end
      end
      return saved_time_entries,unsaved_time_entries
    end #save_time_entries
    
    def total_leaves(leaves)
      total_leaves = 0
      leaves.each do |entry|
         diff_period = (entry.optional_to_leave_date.to_date-entry.spent_on.to_date).to_i
         leave_period = 1
         leave_period += diff_period if diff_period!=0
         total_leaves += leave_period
       end
       return total_leaves
    end
    
    def leave_period(leave)
      diff_period = (leave.optional_to_leave_date.to_date-leave.spent_on.to_date).to_i
      leave_period = 1
      leave_period += diff_period if diff_period!=0
      return leave_period
    end
    
    def leave_period_in_hours(leave)
      return leave_period(leave)*8
    end
    
    def billable_hours(entries, account_type)
      total = 0
      entries.each do |entry|
        if entry.issue.accounting.name.eql?(account_type)
          total += entry.hours
        end
      end
      return total
    end
    
    def logtime_allowed?(user, project)
      return false if user.memberships.find_by_project_id(project).nil?
      return user.memberships.find_by_project_id(project).role.allowed_to?(:log_time)
    end
    def test
      "class test"
    end
  end #ClassMethods
  
  def test
    'instance test'
  end
  
end #TimeEntryExtn

TimeEntry.send(:include,TimeEntryExtn)
