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
 
module TickerHelper
  def html_years(years, colspans)
    str = ""
    years.each_with_index do |year, index|
      str += "<th colspan='#{colspans[index]}'>#{year}</th>"
    end
    str 
  end

  def html_months(months, colspans)
    str = ""
    months.each_with_index do |month, index|
      str += "<th colspan='#{colspans[index]}'>#{month}</th>"
    end
    str 
  end

  def html_weeks(weeks)
    str = ""
    # puts weeks.join(", ")
    weeks.each do |week|
      str += "<th>#{week}</th>"
    end
    str 
  end

  def html_days(days)
    str = ""
    days.each do |day|
      str += "<th>#{day}</th>"
    end
    str
  end
  
  
  def csv_years(years, colspans)
    headers = [l(:label_employee_name),
                "Position",
                 l(:label_total) + " " + l(:field_hours) + " (" + sprintf("%.2f", @th) + ")",
                 l(:label_total) + " " + l(:field_hours) + " on selected projects (" + sprintf("%.2f", @thos) + ")",
                 l(:label_total_bill) + " (" + sprintf("%.2f", @tbh) + ")",
                 l(:label_total_non_bill) + " (" + sprintf("%.2f", @tnbh) + ")"]
    str = headers.join(",") + ","
    years.each_with_index do |year, index|
      str += year.to_s
      (1..colspans[index]).each{|v| 
        str += ","
      }
    end
    str 
  end

  def csv_months(months, colspans)
    str = ",,,,,,"
    months.each_with_index do |month, index|
      str += month.to_s
      (1..colspans[index]).each{|v| 
        str += ","
      }      
    end
    str 
  end

  def csv_weeks(weeks)
    str = ",,,,,,"
    weeks.each do |week|
      str += week.to_s + ","
    end
    str 
  end

  def get_first_sunday(y, m)
    first_day = Date.new(y, m, 1)
    if first_day < @from
      first_day = @from
    end
#    if first_day.wday == 6
#      first_day = first_day + 2.days
#    end
    # puts "first_day.wday #{first_day.wday} :: @from.month #{@from.month} :: @from.year #{@from.year} :: y #{y} :: m#{m}"
    if first_day.wday != 1 && @from.month == m && @from.year == y
        first_day.cweek
    else
        first_day.cweek + 1
    end
    
#    if (first_day.cweek == 1)
#      first_day.cweek
#    elsif first_day.wday == 1
#      Date.new(y, m, (7-first_day.wday)).cweek
#    elsif first_day.wday > 1
#      puts "C: #{Date.new(y, m, 1+(7-first_day.wday)).cweek} #{}"
#      Date.new(y, m, 1+(7-first_day.wday)).cweek
#    else
#      ( (first_day.cweek + 1) == 53)? 1 : (first_day.cweek + 1)
#    end
  end

  def get_last_day(y, m)
    last_day = Date.new(y, m, -1).cweek
    (last_day == 1)? 52 : last_day
  end

  def header
    str = ""
    years = []
    years_colspan = []
    months = []
    months_colspan = []
    weeks = []
    days = []

    (@from.year..@to.year).each do |y|
      years.push(y)
      
      if @columns == "month" || @columns == "week" || @columns == "day"
        mo_start = (@from.year == y) ? @from.month : 1
        mo_end = (@to.year == y) ? @to.month : 12
        cM = 0
        (mo_start..mo_end).each do |m|
          months.push(Date::ABBR_MONTHNAMES[m])
          if @columns == "week"      
            wk_start = get_first_sunday(y, m) #(@from.year == y && @from.month == m) ? @from.cweek : get_first_sunday(y, m)
            wk_end = (@to.year == y && @to.month == m) ? @to.cweek : get_last_day(y, m)
            cm = 0
            # puts "wk_start: #{wk_start};    wk_end: #{wk_end}   #{(wk_start <= wk_end)}"
            if wk_start <= wk_end
              wk_end += 1 if wk_start == wk_end
              (wk_start..wk_end).each do |w|
                weeks.push(w)
                cm += 1
              end
            else              
              (1..wk_end).each do |w|
                weeks.push(w)
                cm += 1
              end
            end
            cM += cm
            months_colspan.push(cm)
          elsif @columns == "day"
            start_date = Date.new
            end_date = Date.new
            cm = 0
            if @from.month == @to.month
              start_date = @from
              end_date = @to
            else
              if @from.month == m
                start_date = @from
                end_date = @from.end_of_month
              elsif @to.month == m
                start_date = Date.new(y,m)
                end_date = @to
              else
                start_date = Date.new(y,m)
                end_date = Date.new(y,m).end_of_month
              end
            end
            (start_date..end_date).each do |d|
              days.push(d.day)
              cm += 1
            end
            cM += cm
            months_colspan.push(cm)
          else
            weeks.push("")
            days.push("")
            months_colspan.push(1)
          end
        end
          
        if @columns == "week" || @columns == "day"
          years_colspan.push( cM )
        else
          years_colspan.push( 13 - mo_start)
        end
        
      else
        years_colspan.push(1)
      end
      
    end
    str += html_years(years, years_colspan)
    str += "</tr><tr>"
    str += html_months(months, months_colspan)
    str += "</tr><tr>"
    str += (@columns == "day")? html_days(days) : html_weeks(weeks)
    str
  end
  
  def header_csv
    str = ""
    years = []
    years_colspan = []
    months = []
    months_colspan = []
    weeks = []

    (@from.year..@to.year).each do |y|
      years.push(y)
      
      if @columns == "month" || @columns == "week"
        mo_start = (@from.year == y) ? @from.month : 1
        mo_end = (@to.year == y) ? @to.month : 12
        cM = 0
        (mo_start..mo_end).each do |m|
          months.push(Date::ABBR_MONTHNAMES[m])
          if @columns == "week"
            wk_start =  get_first_sunday(y, m) # (@from.year == y && @from.month == m) ? @from.cweek : get_first_sunday(y, m)
            wk_end = (@to.year == y && @to.month == m) ? @to.cweek : get_last_day(y, m)
            cm = 0
            if wk_start <= wk_end
               wk_end += 1 if wk_start == wk_end
              (wk_start..wk_end).each do |w|
                weeks.push(w)
                cm += 1
              end
            else              
              (1..wk_end).each do |w|
                weeks.push(w)
                cm += 1
              end
            end
            
            cM += cm
            months_colspan.push(cm)
          else
            weeks.push("")
            months_colspan.push(1)
          end
        end
          
        if @columns == "week"
          years_colspan.push( cM )
        else
          years_colspan.push( 13 - mo_start)
        end
        
      else
        years_colspan.push(1)
      end
      
    end
            
    str += csv_years(years, years_colspan)
    str += "\n"
    str += csv_months(months, months_colspan)
    str += "\n"
    str += csv_weeks(weeks)
    str
  end

  def print_entries(entries)
    index = 0
    str = ""
    nonbillable = (@show_only == "both" || @show_only == "non_billable")
    billable = (@show_only == "both" || @show_only == "billable")
    case @columns
      when 'year'
        count = 0
        @from.upto(@to) do |d|
          entrys = entries.select{|e| e.spent_on.year == d.year && e.spent_on.month == d.month && e.spent_on.day == d.day }
          entries = entries - entrys
          if entrys.size > 0
            for entry in entrys
              if !entry.billable && nonbillable
                count += entry.hours
              elsif entry.billable && billable
                count += entry.hours
              end
            end
          end
          if (d.month == 12 && d.day == 31 ) || @to == d    
            if count == 0
              str += "<td> - </td>"
              @tall[index] = (@tall[index] && @tall[index] > 0)? @tall[index] : 0
              index += 1
            else
              str += "<td>" + html_hours("%.2f" % count.to_f).to_s + "</td>"
              @tall[index] = (@tall[index] == nil)? count.to_f : (@tall[index] + count.to_f)
              index += 1
            end
            count = 0
          end
        end
      when 'month'
        count = 0
        @from.upto(@to) do |d|
          entrys = entries.select{|e| e.spent_on.year == d.year && e.spent_on.month == d.month && e.spent_on.day == d.day }
          entries = entries - entrys
          if entrys.size > 0
            for entry in entrys
              if !entry.billable && nonbillable
                count += entry.hours
              elsif entry.billable && billable
                count += entry.hours
              end
            end
          end
          
          if (d.day == 1 && d != @from) || @to == d
            if count == 0
              str += "<td> - </td>"
              @tall[index] = (@tall[index] && @tall[index] > 0)? @tall[index] : 0
              index += 1
            else
              str += "<td>" + html_hours("%.2f" % count.to_f).to_s + "</td>"
              @tall[index] = (@tall[index] == nil)? count.to_f : (@tall[index] + count.to_f)
              index += 1
            end
            count = 0
          end
        end
      when 'week'
        count = 0
        @from.upto(@to) do |d|
          entrys = entries.select{|e| e.spent_on == d }
          entries = entries - entrys
          # c = 0
          if entrys.size > 0
            for entry in entrys
              if !entry.billable && nonbillable
                count += entry.hours
                # c += entry.hours
              elsif entry.billable && billable
                count += entry.hours
                # c += entry.hours
              end
            end
          end  
          # puts "#{d} - #{d.wday} - #{c}"
          
          if (d.wday == 0)
            
            if count == 0
              str += "<td> - </td>"
              @tall[index] = (@tall[index] && @tall[index] > 0)? @tall[index] : 0
              index += 1
            else
              str += "<td>" + html_hours("%.2f" % count.to_f).to_s + "</td>"
              @tall[index] = (@tall[index] == nil)? count.to_f : (@tall[index] + count.to_f)
              index += 1
            end
            count = 0
          elsif d == @to
            if count == 0
              str += "<td> - </td>"
            else
              str += "<td>" + html_hours("%.2f" % count.to_f).to_s + "</td>"
            end
            @tall[index] = (@tall[index] == nil)? count.to_f : (@tall[index] + count.to_f)
            index += 1
          end
          
        end
      when 'day'
        count = 0
        @from.upto(@to) do |d|
          entrys = entries.select{|e| e.spent_on == d }
          entries = entries - entrys
          # c = 0
          if entrys.size > 0
            for entry in entrys
              if !entry.billable && nonbillable
                count += entry.hours
                # c += entry.hours
              elsif entry.billable && billable
                count += entry.hours
                # c += entry.hours
              end
            end
          end 
            
            if count == 0
              str += "<td> - </td>"
              @tall[index] = (@tall[index] && @tall[index] > 0)? @tall[index] : 0
              index += 1
            else
              str += "<td>" + html_hours("%.2f" % count.to_f).to_s + "</td>"
              @tall[index] = (@tall[index] == nil)? count.to_f : (@tall[index] + count.to_f)
              index += 1
            end
            count = 0
          
        end 
       
    end
    str
  end
  
  
  def parse_date(date)
    Date.new(date.year, date.month, date.day)
  end
  
  
   def print_entries_csv(entries)
    index = 0
    str = ""
    nonbillable = (@show_only == "both" || @show_only == "non_billable")
    billable = (@show_only == "both" || @show_only == "billable")
    case @columns
      when 'year'
        count = 0
        @from.upto(@to) do |d|
          entrys = entries.select{|e| e.spent_on.year == d.year && e.spent_on.month == d.month && e.spent_on.day == d.day }
          entries = entries - entrys
          if entrys.size > 0
            for entry in entrys
              if !entry.billable && nonbillable
                count += entry.hours
              elsif entry.billable && billable
                count += entry.hours
              end
            end
          end
          if (d.month == 12 && d.day == 31 ) || @to == d    
            if count == 0
              str += "-,"
              @tall[index] = (@tall[index] && @tall[index] > 0)? @tall[index] : 0
              index += 1
            else
              str += sprintf("%.2f" % count.to_f) + ","
              @tall[index] = (@tall[index] == nil)? count.to_f : (@tall[index] + count.to_f)
              index += 1
            end
            count = 0
          end
        end
      when 'month'
        count = 0
        @from.upto(@to) do |d|
          entrys = entries.select{|e| e.spent_on.year == d.year && e.spent_on.month == d.month && e.spent_on.day == d.day }
          entries = entries - entrys
          if entrys.size > 0
            for entry in entrys
              if !entry.billable && nonbillable
                count += entry.hours
              elsif entry.billable && billable
                count += entry.hours
              end
            end
          end
          if (d.day == 1 && d != @from) || @to == d
            if count == 0
              str += "-,"
              @tall[index] = (@tall[index] && @tall[index] > 0)? @tall[index] : 0
              index += 1
            else
              str += sprintf("%.2f" % count.to_f) + ","
              @tall[index] = (@tall[index] == nil)? count.to_f : (@tall[index] + count.to_f)
              index += 1
            end
            count = 0
          end
        end
      when 'week'
        count = 0
        @from.upto(@to) do |d|
          entrys = entries.select{|e| e.spent_on == d }
          entries = entries - entrys
          if entrys.size > 0
            for entry in entrys
              if !entry.billable && nonbillable
                count += entry.hours
              elsif entry.billable && billable
                count += entry.hours
              end
            end
          end  
            
          if (d.wday == 0)
            if count == 0
              str += "-,"
              @tall[index] = (@tall[index] && @tall[index] > 0)? @tall[index] : 0
              index += 1
            else
              str += sprintf("%.2f" % count.to_f) + ","
              @tall[index] = (@tall[index] == nil)? count.to_f : (@tall[index] + count.to_f)
              index += 1
            end
            count = 0
          elsif d == @to
            if count == 0
              str += "-,"
            else
              str += sprintf("%.2f" % count.to_f) + ","
            end
            @tall[index] = (@tall[index] == nil)? count.to_f : (@tall[index] + count.to_f)
            index += 1
          end
        end          
    end
    str
  end
  
  
  def default_activity
    Enumeration.activities.default.id if Enumeration.activities.default
  end  
    
  def labelled_tabular_remote_form_for(name, object, options, &proc)
    options[:html] ||= {}
    options[:html][:class] = 'tabular' unless options[:html].has_key?(:class)
    remote_form_for(name, object, options.merge({ :builder => TabularFormBuilder, :lang => current_language}), &proc)
  end    
  
  def pagination_links_entries(paginator, count=nil, options={})
    page_param = options.delete(:page_param) || :page
    url_param = params.dup
    # don't reuse params if filters are present
    url_param.clear if url_param.has_key?(:set_filter)

    html = ''
    html << link_to_remote(('&#171; ' + l(:label_previous)),
                            {:update => options[:container_id],
                             :url => url_param.merge(page_param => paginator.current.previous),
                             :complete => 'window.scrollTo(0,0)'},
                            {:href => url_for(:params => url_param.merge(page_param => paginator.current.previous))}) + ' ' if paginator.current.previous

    html << (pagination_links_each(paginator, options) do |n|
      link_to_remote(n.to_s,
                      {:url => {:params => url_param.merge(page_param => n)},
                       :update => options[:container_id],
                       :complete => 'window.scrollTo(0,0)'},
                      {:href => url_for(:params => url_param.merge(page_param => n))})
    end || '')

    html << ' ' + link_to_remote((l(:label_next) + ' &#187;'),
                                 {:update => options[:container_id],
                                  :url => url_param.merge(page_param => paginator.current.next),
                                  :complete => 'window.scrollTo(0,0)'},
                                 {:href => url_for(:params => url_param.merge(page_param => paginator.current.next))}) if paginator.current.next

    unless count.nil?
      html << [" (#{paginator.current.first_item}-#{paginator.current.last_item}/#{count})", per_page_links_entries(paginator.items_per_page, options[:container_id])].compact.join(' | ')
    end

    html
  end
  
  def per_page_links_entries(selected=nil, container_id="")
    url_param = params.dup
    url_param.clear if url_param.has_key?(:set_filter)

    links = Setting.per_page_options_array.collect do |n|
      n == selected ? n : link_to_remote(n, {:update => container_id, :url => params.dup.merge(:per_page => n)},
                                            {:href => url_for(url_param.merge(:per_page => n))})
    end
    links.size > 1 ? l(:label_display_per_page, links.join(', ')) : nil
  end
  
  
def leave_entries_to_csv(leaves, projects, option)
    ic = Iconv.new(l(:general_csv_encoding), 'UTF-8')
    export = StringIO.new
    CSV::Writer.generate(export, l(:general_csv_separator)) do |csv|
      #headers
      headers = [l("Employee Name"),
                 l("Leave type"),
                 l("Details")
                ]
      headers.insert(0, l("Project")) if option.eql?("")
      
      entries = leaves.group_by(&:spent_on)
      entries.keys.sort.reverse.each do |day|
        headers.push( day )
      end

      csv << headers.collect { |c| begin; ic.iconv(c.to_s); rescue; c.to_s; end}
      
      #csv lines
      fields = []
      entries.keys.sort.reverse.each do |day|
        #spaces = option.eql?("") ? 3 : 2
        #entries.keys.sort.reverse.each do |period|
        #  if period.eql?(day)
            #fields = [l(:label_total)]
            #for i in 0...spaces
            # fields.push("")
            #end
            #if period.eql?(day)
            # fields.push( "#{TimeEntry.total_leaves(entries[period])} day(s)" )
            #else
            # fields.push("")
            #end
        #  else
        #    spaces += 1
        #  end
        #end
        #csv << fields.collect {|c| begin; ic.conv(c.to_s); rescue; c.to_s; end}
        proj = ''
        if option.eql?("")
          for project in projects
            entries[day].each do |entry|
              if entry.user.member_of?(project)
                unless proj.eql?(project)
                  fields = [l(project.name)]
                end
                proj = project
                spaces = 5 + leaves.length
                for i in 0...spaces
                  fields.push("")
                end
                csv << fields.collect {|c| begin; ic.conv(c.to_s); rescue; c.to_s; end}
                
                fields = ["",l(entry.user.name), l(entry.leave_type), l(entry.details)]
                entries.keys.sort.reverse.each do |period|
                  if period.eql?(day)
                    fields.push("#{TimeEntry.leave_period(entry)} day(s)")
                  else
                    fields.push("")
                  end
                end
                csv << fields.collect {|c| begin; ic.conv(c.to_s); rescue; c.to_s; end}
              end
            end
          end
        else
          entries[day].each do |entry|
            fields = [l(entry.user.name), l(entry.leave_type), l(entry.details)]
            entries.keys.sort.reverse.each do |period|
              if period.eql?(day)
                fields.push("#{TimeEntry.leave_period(entry)} day(s)")
              else
                fields.push("")
              end
            end
            csv << fields.collect {|c| begin; ic.conv(c.to_s); rescue; c.to_s; end}
          end
        end
        
      end
    end
    export.rewind
    export
  end  
  
  def highlight_allocated_class(thos,mh,proj_id,summary)
    # thos = total_hours_on_selected
    # mh = max_hours
    thos.to_i > mh.to_i && (proj_id.to_i.eql?(summary[:project_id]) || summary[:admin]) ? 'redFont' : ''
  end

end
