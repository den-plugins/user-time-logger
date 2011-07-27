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
require 'redmine'

RAILS_DEFAULT_LOGGER.info 'Starting tick plugin for Redmine'

# Redmine simple CI plugin
Redmine::Plugin.register :user_time_logger do
  name 'Issue Time Ticker'
  author 'Exist Global'
  description 'A generic plugin for logging time spent on the issue by a particular user in Redmine.s'
  version '1.0'
  
end

#require File.dirname(__FILE__) + '/lib/time_entry_extn'
require File.dirname(__FILE__) + '/app/models/time_entry_extn'
