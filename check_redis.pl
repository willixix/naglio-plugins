#!/usr/bin/perl -w
#
# ============================== SUMMARY =====================================
#
# Program : check_redis.pl
# Version : 0.8 alpha1
# Date    : Aug 23, 2013
# Author  : William Leibzon - william@leibzon.org
# Licence : GPL - summary below, full text at http://www.fsf.org/licenses/gpl.txt
#
# =========================== PROGRAM LICENSE =================================
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
#
# ===================== INFORMATION ABOUT THIS PLUGIN =========================
#
# This is Redis Server Check plugin. It gets stats variables and allows to set
# thresholds on their value or their rate of change. It can measure response time,
# hitrate, memory utilization, check replication sync and more. It can also test
# data in a specified key (if necessary doing average or sum on range).
#
# Plugin returns stats variables as performance data for further nagios 2.0
# post-processing, you can find graph templates for PNP4Nagios at:
#   http://william.leibzon.org/nagios/
#
# This program is written and maintained by:
#   William Leibzon - william(at)leibzon.org
#
# ============================= SETUP NOTES ====================================
#
# Make sure to install Redis perl library from CPAN first.
#
# Next for help and to see what parameters this plugin accepts do:
#  ./check_redis.pl --help
#
# This plugin checks Redis NoSQL database status variables, measures its response
# time and if specified allows to set thresholds on one or more key data. You can
# set thresholds for data in stats variables and some of them are also conveniently
# available as long options with special threshold syntax. Plugin also calculates
# statistics such as Hitrate (calculated as rate of change of hits/misses) and
# memory use and can check replication delay.
#
# All variables can be returned as performance data for graphing and pnp4nagios
# template should be available with this plugin on the site you downloaded it from.

# 1. Connection Parameters
#
#   The connection parameters are "-H hostname", "-p port", "-D database" and
#   "-C password_file" or "-x password". Specifying hostname is required, if you
#   run locally specify it as -H 127.0.0.1. Everything else is optional and rarely
#   needed. Default port is 6337. Database name (usually a numeric id) is probably
#   only needed if you use --query option. Password can be passed on a command
#   line with -x but its safer to read read it from a file or change in the code
#   itself if you do use authentication.
#
# 2. Response Time, HitRate, Memory Utilization, Replication Delay
#
#   To get response time you use "-T" or "--response_time=" option. By itself
#   it will cause output of response time at the status line. You can also use
#   it as "-T warn,crit" to specify warning and critical thresholds.
#
#   To get hitrate the option is "-R" or "--hitrate=". If previous performance
#   data is not feed to plugin (-P option, see below) the plugin calculates
#   it as total hitrate over life of redis process. If -P is specified and
#   previous performance data is fed back, the data is based on real hitrate
#   (which can show spikes and downs) with lifelong info also given in paranthesis
#   The data is based on keyspace_hits and keyspace_misses stats variables.
#   As with -T you can specify -R by itself or with thresholds as -R warn,crit
#
#   Memory utilization is percent of real memory used by Redis out of total
#   memory on the system. To be able to calculate it plugin needs to known
#   amount of memory your system has which you specify with "-M" or "--total_memory="
#   option. Memory utilization option itself is lower "-m" or "--memory_utilization="
#   and you can specify threshold for it as "-m warn,crit"
#
#   Replication delay threshold option "-R" or "--replication_delay=" is used
#   to check replication with data from "master_last_io_seconds_ago" stats and
#   valid only on slave servers. Other variables maybe checked for this later
#   with more complex functionality, so it was chosen to do this as separate
#   option rather than directing people to check that variable.
#
# 3. Checks on Redis Status Variables
#
#   All status variables from redis can be checked with the plugin. For some
#   status variables separate long option is provided to specify threshold.
#       i.e. --connected_clients=<thresholds>
#
#   This is a new alternative to specifying all variables together with -a
#   (--variables) option. For example:
#       -a connected_clients,blocked_clients
#   When you do above results are included in status output line and you
#   are required to specify thresholds with -w or --warn and -c or --crit
#   with exactly number of thresholds as a number of variables specified
#   in -a. If you simply want variable values on status line without specifying
#   any threshold, use ~ in place of threshold value or skip value but specify
#   all appropriate commas. For example:
#           -a connected_clients,blocked_clients -w ~,~ -c ~,~
#      OR   -a connected_clients,blocked_clients -w , -c ,
#
#   If you use new syntax with a long option for specific stats variables, you
#   can specify list of one or more threshold specifiers which can be any of:
#       NAME:<string>   - Overrides name for this variable for use in status and PERF output
#       PATTERN:<regex> - Regular Expression that allows to match multiple data results
#       WARN:threshold  - warning alert threshold
#       CRIT:threshold  - critical alert threshold
#         Threshold is a value (usually numeric) which may have the following prefix:
#           > - warn if data is above this value (default for numeric values)
#           < - warn if data is below this value (must be followed by number)
#           = - warn if data is equal to this value (default for non-numeric values)
#           ! - warn if data is not equal to this value
#         Threshold can also be specified as a range in two forms:
#           num1:num2  - warn if data is outside range i.e. if data<num1 or data>num2
#           \@num1:num2 - warn if data is in range i.e. data>=num1 && data<=num2
#       ABSENT:OK|WARNING|CRITICAL|UNKNOWN - Nagios alert (or lock of thereof) if data is absent
#       ZERO:OK|WARNING|CRITICAL|UNKNOWN   - Nagios alert (or lock of thereof) if result is 0
#       DISPLAY:YES|NO - Specifies if data should be included in nagios status line output
#       PERF:YES|NO    - Output in performance data or not (always YES if -F option is used)
#       UOM:<string>   - Unit Of Measurement symbol to add to perf data - 'c','%','s','B'
#			 This is used by programs that graph perf data such as PNP
#
#   These can be specified in any order separated by ",". For example:
#      --connected_clients=CRIT:>100,WARN:>50,ABSENT:CRITICAL,ZERO:OK,DISPLAY:YES,PERF:YES
#
#   Variables that are not known to plugin and don't have specific long option (or even if
#   they do) can be specified using general long option --check or --option or -o
#   (all are aliases for same option):
#      --check=NAME:connected_clients,CRIT:>100,WARN:>50,ABSENT:CRITICAL,DISPLAY:YES,PERF:YES
#
#   Then NAME is used to specify what to match and multiple data vars maybe matched
#   with PATTERN regex option (and please only use PATTERN with --check and not confuse
#   plugin by using it in a named long option). Either NAME or PATTERN are required.
#
# 4. Calculating and using Rate of Change for Variables
#
#   If you want to check rate of change rather than actual value you can do this
#   by specifying it as '&variable' such as "&total_connections_received" or
#   as "variable_rate" which is "total_connections_received_rate" and is similar
#   to 'connected_clients' variable. By default it would be reported in the output
#   as 'variable_rate' though '&variable' is a format used internally by plugin.
#
#   As an alternative you can specify how to label these with --rate_label
#   option where you can specify prefix and/or suffix. For example '--rate_label=dt_'
#   would have the output being "dt_total_connections_received' where as
#   '--rate_label=,_rate' is plugin default giving 'total_connections_received_rate'.
#   You can use these names with -a and -A such as:
#       --rate_label=,_rate -a total_connections_received_rate -w 1000 -c ~
#   Note that --rate_label will not work with new variable-named options, the
#   only way to change default if you use that is to modify code and change
#   $o_rprefix and $o_rsuffix variables default values.
#
#   Now in order to be able to calculate rate of change, the plugin needs to
#   know values of the variables from when it was run the last time. This
#   is done by feeding it previous performance data with a -P option.
#   In commands.cfg this would be specified as:
#     -P "$SERVICEPERFDATA$"
#   And don't forget the quotes, in this case they are not just for documentation.
#
# 5. Threshold Specification
#
#   The plugin fully supports Nagios plug-in specification for specifying thresholds:
#     http://nagiosplug.sourceforge.net/developer-guidelines.html#THRESHOLDFORMAT
#
#   And it supports an easier format with the following one-letter prefix modifiers:
#     >value : issue alert if data is above this value (default for numeric value)
#     <value : issue alert if data is below this value (must be followed by number)
#     =value : issue alert if data is equal to this value (default for non-numeric)
#     !value : issue alert if data is NOT equal to this value
#   (because > and < are interpreted by shell you may need to specify this in quotes)
#   There are also two specifications of range formats as with other nagios plugins:
#     number1:number2   issue alert if data is OUTSIDE of range [number1..number2]
#	                i.e. alert if data<$number1 or data>$number2
#     @number1:number2  issue alert if data is WITHIN range [number1..number2]
#		        i.e. alert if data>=$number and $data<=$number2
#
#   The plugin will attempt to check that WARNING value is less than CRITICAL
#   (or greater for <). A special prefix modifier '^' can be used to disable these
#   checks. A quick example of such special use is '--warn=^<100 --crit=>200' which
#   means warning alert if value is < 100 and critical alert if its greater than 200.
#
# 6. Performance Data
#
#   With '-f' option values of all variables you specified in -a as well as
#      response time from -T (response time),
#      hitrate from -R,
#      memory utilization from -m
#   and other data are reported back out as performance data for Nagios graphing programs.
#
#   You may also directly specify which variables are to be return as performance data
#   with '-A' option. If you use '-A' by itself and not specify any variables or use
#   special value of '*' (as in '-A *') the plugin will output all variables which is useful
#   for finding what data you can check with this plugin.
#
#   The plugin will output threshold values as part of performance data as specified at
#     http://nagiosplug.sourceforge.net/developer-guidelines.html#AEN201
#   And don't worry about using non-standard >,<,=,~ prefixes, all of that would get
#   converted into nagios threshold format for performance output
#
#   The plugin is smart enough to add 'c' suffix for known COUNTER variables to
#   values in performance data. Known variables are specified in an array you can
#   find at the top of the code (further below) and plugin author does not claim
#   to have identified all variables correctly. Please email if you find an error
#   or want to add more variables.
#
#   As noted above performance data is also used to calculate rate of change
#   by feeding it back with -P option. In that regard even if you did not specify
#   -f or -A but you have specified &variable, its actual data would be sent out
#   in performance output. Additionally last time plugin was run is also in
#   performance data as special _ptime variable.
#
# 7. Query Option and setting thresholds for data in Redis Database
#
#   With -q (--query) option the plugin can retrieve data from Redis database
#   which become new variables you can then check thresholds on. Currently it
#   supports getting single key values with GET and getting range or values (or
#   everything in list) with LRANGE and finding their Average or Min or Max or Sum.
#   The option maybe repeated more than once. The format for this option is:
#
#      -q, --query=query_type,key[:varname]<,list of threshold specifiers>
#
#  query_type is one of:
#	GET   - get one string value
#       LLEN  - returns number of items in a list
#	LRANGE:AVG:start:end - retrieve list and average results
#	LRANGE:SUM:start:end - retrieve list and sum results
#	LRANGE:MIN:start:end - retrieve list and return minimum
#	LRANGE:MAX:start:end - retrieve list and return maximum
#       HLEN  - returns number of items in a hash [TODO]
#       HGET:name  - get specific hash key 'name' [TODO]
#       HEXISTS:name - returns 0 or 1 depending on if specified hash key 'name' exists [TODO]
#       SLEN  - returns number of items in a set [TODO, SCARD redis opp]
#       SEXISTS:name - returns 0 or 1 depending on if set member 'name' exists [SISMEMBER, TODO]
#       ZLEN  - returns number of items in a sorted set [TODO, ZCARD redis opp]
#       ZCOUNT:min:max - counts number of items in sorted set with scores within the given values
#       ZRANGE:AVG:min:max - retrieve sorted set members from min to max and average results
#       ZRANGE:SUM:min:max - retrieve sorted set members from min to max and sum results
#       ZRANGE:MIN:min:max - retrieve sorted set members from min to max list and return minimum
#       ZRANGE:MAX:min:max- retrieve sorted set members from min to max and return maximum
#   For LRANGE if you do not specify start and end, then start will be  0 and end
#   is last value in the list pointed to by this key (found by using llen).
#
#   Key is the Redis key name to be retrieved and optionally you can add ":varname"
#   after it which specifies what to name plugin variable based on this data -
#   based on what you specify here is how it will be displayed in the status
#   line and performance data, default is same as Redis key name.
#
#   After these key name you specify list of thresholds in the same format as
#   variable-based long options described in section 3. Again the list of the
#   possible specifiers are:
#      WARN:threshold
#      CRIT:threshold
#      ABSENT:OK|WARNING|CRITICAL|UNKNOWN  - what to do if data is not available
#      ZERO:OK|WARNING|CRIICAL|UNKNOWN	   - what to do if data is 0 (rarely needed)
#      DISPLAY:YES|NO			   - display on status line or not (default YES)
#      PERF:YES|NO	 		   - output in perf data or not
#
#   You can also optionally use -a, -w and -c to check data from the query instead
#   of specifying thresholds as part of query option itself And remember that you if
#   you need to check multiple keys you just repeat --query option more than once.
#
# 8. Example of Nagios Config Definitions
#
# Sample command and service definitions are below:
#
# define command {
#    command_name        check_redis_new
#    command_line        $USER1$/check_redis.pl -H $HOSTADDRESS$ -p $ARG1$ -T $ARG2$ -R -A -M $_HOSTSYSTEM_MEMORY$ -m $ARG3$ -a $ARG4$ -w $ARG5$ -c $ARG6$ -f -P "$SERVICEPERFDATA$"
# }
#
# Arguments and thresholds are:
#  $ARG1 : Port
#  $ARG2 : response time thresholds
#  $ARG3 : memory utilization thresholds
#  $ARG4 : additional variables to be checked
#  $ARG5 : warning thresholds for those variables
#  $ARG6 : critical thresholds for those variables
#
# define service {
#        use                     prod-service
#        hostgroups              redishosts
#        service_description     Redis
#        check_command           check_redis_new!6379!"1,2"!"80,90"!blocked_clients,connected_clients!50,~!100,~
# }
#
# define host {
#         use             prod-server
#         host_name       redis.mynetwork
#         address         redis.mynetwork
#         alias           Redis Stat Server
#         hostgroups      linux,redishosts
#        _SYSTEM_MEMORY  '8G'
# }
#
# Example of command-line use:
#   /usr/lib/nagios/plugins/check_redis.pl -H localhost -a 'connected_clients,blocked_clients' -w ~,~ -c ~,~ -m -M 4G -A -R -T -f -v
#
# In above the -v option means "verbose" and with it plugin will output some debugging information
# about what it is doing. The option is not intended to be used when plugin is called from nagios itself.
#
# Example of using query and variable-based long options with debug enabled as well (-v):
#
# ./check_redis.pl -H localhost -p 6379 -D 1 --query LRANGE:AVG:0:,MyColumn1:Q1,ABSENT:WARNING,WARN:300,CRIT:500,DISPLAY:YES,PERF:NO
#   --query GET,MyKey:K1,ABSENT:CRITICAL "--connected_clients=WARN:<2,CRIT:>100,ZERO:OK,ABSENT:WARNING,DISPLAY:YES,PERF:YES"
#
# ======================= VERSION HISTORY and TODO ================================
#
# The plugins is written by reusing code my check_memcached.pl which itself is based
# on check_mysqld.pl. check_mysqld.pl has history going back to 2004.
#
#  [0.4  - Mar 2012] First version of the code based on check_mysqld.pl 0.93
#		     and check_memcached.pl 0.6. Internal work, not released.
#		     Version 0.4 because its based on a well developed code base
#  [0.41 - Apr 15, 2012] Added list of variables array and perf_ok regex.
#			 Still testing internally and not released yet.
#  [0.42 - Apr 28, 2012] Added total_keys, total_expires, nice uptime_info
#			 and memory utilization
#  [0.43 - May 31, 2012] Release candidate. More documentation added
#			 replacing check_memcached examples. Bugs fixed.
#			 Made "_rate" as default rate variables suffix in
#		         place of &delta. Changed -D option to -r.
#
#  [0.5  - Jun 01, 2012] First official release will start with version 0.5
#			 Documentation changes, but no code updates.
#  [0.51 - Jun 16, 2012] Added support to specify filename to '-v' option
#			 for debug output and '--debug' as alias to '--verbose'
#  [0.52 - Jul 10, 2012] Patch by Jon Schulz to support credentials with -C
#			 (credentials file) and addition by me to support
#			 password as command argument.
#  [0.53 - Jul 15, 2012] Adding special option to do query on one redis key and
#                        and do threshold checking of results if its numeric
#
#  [0.6  - Jul 17, 2012] Rewrote parts of thresholds checking code and moved code
#			 that checks and parses thresholds from main into separate
#			 functions that are to become part of plugin library.
#			 Added support for variable thresholds specified as:
#			   option=WARN:threshold,CRIT:threshold,ABSENT:OK|WARNING|CRITICAL,ZERO:..
#			 which are to be used for stats-variable based long options such as
#			   --connected_clients=WARN:threshold,CRIT:threshold
#			 and added DISPLAY:YES|NO and PERF specifiers for above too.
#			 Added -D option to specify database needed for --query
#  [0.61 - Aug 03, 2012] Added more types of key query for lists, sets, hashes
#			 and options to find number of elements in a list/set/hash.
#		         New options added are:
#			   LLEN,HLEN,SLEN,ZLEN,HGET,HEXISTS,SEXISTS,ZRANGE
#
#  [0.7  - Aug 28, 2012] A lot of internal rewrites in the library. Its now not just a
#		         a set of functions, but a proper object library with internal
#			 variables hidden from outside. Support has also been added for
#		         regex matching with PATTERN specifier and for generalized
#                        --check option that can be used where specific long option is
#			 not available. For use with that option also added UOM specifier.
#		         Also added checkin 'master_last_io_seconds_ago' (when link is down)
#			 for when replication_delay info is requested.
#  [0.71 - Sep 03, 2012] Fixed bug in a new library related to when data is missing
#  [0.72 - Oct 05, 2012] Fixed bug reported by Matt McMillan in specified memory size
#			 when KB are used. Fixed bugs in adding performance data that
# 			 results in keyspace_hits, keyspace_misses, memory_utilization
#			 having double 'c' or '%' in perfdata. Added contributors section.
#  [0.73 - Mar 23, 2013] Fixed bug in parse_threshold function of embedded library
#
# TODO or consider for future:
#
#  1. Library Enhancements (will apply to multiple plugins that share common code)
#     (a) Add '--extra-opts' to allow to read options from a file as specified
#         at http://nagiosplugins.org/extra-opts. This is TODO for all my plugins
#     (b) [DONE]
#	  In plans are to allow long options to specify thresholds for known variables.
#         These would mean you specify '--connected_clients' in similar way to '--hitrate'
#         Internally these would be converged into -A, -w, -c as appropriate and used
#         together with these options. So in practice it will now allow to get any data
#         just a different way to specify options for this plugin.
#     (c) Allow regex when selecting variable name(s) with -a, this will be enabled with
#	  a special option and not be default
#	  [DONE]
#
#  2. REDIS Specific
#     (a) Add option to check from master that slave is connected and working.
#     (b) Look into replication delay from master and how it can be done. Look
#         for into on replication_delay from slave as well
#     (c) How to better calculate memory utilization and get max memory available
#         without directly specifying it
#     (d) Maybe special options to measure cpu use and set thresholds
#
#  Others are welcome recommend a new feature to be added here. If so please email to
#         william@leibzon.org.
#  And don't worry, I'm not a company with some hidden agenda to use your idea
#  but an actual person who you can easily get hold of by email, find on forums
#  and on Nagios conferences. More info on my nagios work is at:
#         http://william.leibzon.org/nagios/
#  Above site should also have PNP4Nagios template for this and other plugins.
#
# ============================ LIST OF CONTRIBUTORS ===============================
#
# The following individuals have contributed code, patches, bug fixes and ideas to
# this plugin (listed in last-name alphabetical order):
#
#   William Leibzon
#   Matthew Litwin
#   Matt McMillan
#   Jon Schulz
#   M Spiegle
#
# ============================ START OF PROGRAM CODE =============================

use strict;
use IO::Socket;
use Time::HiRes;
use Text::ParseWords;
use Getopt::Long qw(:config no_ignore_case);
use Redis;
use Naglio;

# default hostname, port, database, user and password, see NOTES above
my $HOSTNAME= 'localhost';
my $PORT=     6379;
my $PASSWORD= undef;
my $DATABASE= undef;

# Add path to additional libraries if necessary
use lib '/usr/lib/nagios/plugins';
our $TIMEOUT;
our %ERRORS;
eval 'use utils qw(%ERRORS $TIMEOUT)';
if ($@) {
 $TIMEOUT = 20;
 %ERRORS = ('OK'=>0,'WARNING'=>1,'CRITICAL'=>2,'UNKNOWN'=>3,'DEPENDENT'=>4);
}

my $Version='0.73';

# This is a list of known stat and info variables including variables added by plugin,
# used in order to designate COUNTER variables with 'c' in perfout for graphing programs
# The format is:
#        VAR_NAME => [ TYPE, PerfSuffix, DESCRIPTION]
# If option has description, the variable will also become available as a long option so for example
# you can specify "--connected_clients=WARN,CRIT" instead of specifying "-a connected_clients -w WARN -c CRIT'
my %KNOWN_STATUS_VARS = (
	 'memory_utilization' => [ 'status', 'GAUGE', '%' ],      					# calculated by plugin
	 'redis_version' => [ 'status', 'VERSION', '' ],						# version string variable
	 'response_time' => [ 'status','GAUGE', 's' ],							# measured by plugin
	 'hitrate' => [ 'status', 'GAUGE', '%' ],							# calculated by plugin
	 'total_keys' => [ 'status','GAUGE', '', 'Total Number of Keys on the Server' ],
	 'total_expires' => [ 'status','GAUGE', '', 'Number of Expired Keys for All DBs' ],
	 'last_save_time' => [ 'status', 'GAUGE', 's' ],
	 'bgsave_in_progress' => [ 'status', 'BOOLEAN', '' ],
	 'vm_enabled' => [ 'status', 'BOOLEAN', '' ],
	 'uptime_in_seconds' => [ 'status', 'COUNTER', 'c' ],
	 'total_connections_received' => [ 'status', 'COUNTER', 'c', 'Total Connections Received' ],
	 'used_memory_rss' => [ 'status', 'GAUGE', 'B', 'Resident Set Size, Used Memory in Bytes' ],  	# RSS - Resident Set Size
	 'used_cpu_sys' => [ 'status', 'GAUGE', '', 'Main Process Used System CPU' ],
	 'redis_git_dirty' => [ 'status', 'BOOLEAN', '', 'Git Dirty Set Bit' ],
	 'loading' => [ 'status', 'BOOLEAN', '' ],
	 'latest_fork_usec' => [ 'status', 'GAUGE', '' ],
	 'connected_clients' => [ 'status', 'GAUGE', '', 'Total Number of Connected Clients' ],
	 'used_memory_peak_human' => [ 'status', 'GAUGE', '' ],
	 'mem_allocator' => [ 'status', 'TEXTINFO', '' ],
	 'uptime_in_days' => [ 'status', 'COUNTER', 'c', 'Total Uptime in Days' ],
	 'keyspace_hits' => [ 'status', 'COUNTER', 'c', 'Total Keyspace Hits' ],
	 'client_biggest_input_buf' => [ 'status', 'GAUGE', '' ],
	 'gcc_version' => [ 'status', 'TEXTINFO', '' ],
	 'changes_since_last_save' => [ 'status', 'COUNTER', 'c' ],
	 'arch_bits' => [ 'status', 'TEXTINFO', '' ],
	 'lru_clock' => [ 'status', 'GAUGE', '' ], 	# LRU is page replacement algorithm (least recently used), I'm unsure what this represents though
	 'role' => [ 'status', 'SETTING', '' ],
	 'multiplexing_api' => [ 'status', 'SETTING' , '' ],
	 'slave' => [ 'status', 'TEXTDATA', '' ],
	 'pubsub_channels' => [ 'status', 'GAUGE', '', 'Number of Pubsub Channels' ],
	 'redis_git_sha1' => [ 'status', 'TEXTDATA', '' ],
	 'used_cpu_user_children' => [ 'status', 'GAUGE', '', 'Child Processes Used User CPU' ],
	 'process_id' => [ 'status', 'GAUGE', '' ],
	 'used_memory_human' => [ 'status', 'GAUGE', '' ],
	 'keyspace_misses' => [ 'status', 'COUNTER', 'c', 'Keyspace Misses' ],
	 'used_cpu_user' => [ 'status', 'GAUGE', '', 'Main Process Used User CPU' ],
	 'total_commands_processed' => [ 'status', 'COUNTER', 'c', 'Total Number of Commands Processed from Start' ],
	 'mem_fragmentation_ratio' => [ 'status', 'GAUGE', '', 'Memory Fragmentation Ratio' ],
	 'client_longest_output_list' => [ 'status', 'GAUGE', '' ],
	 'blocked_clients' => [ 'status', 'GAUGE', '', 'Number of Currently Blocked Clients' ],
	 'aof_enabled' => [ 'status', 'BOOLEAN', '' ],
	 'evicted_keys' => [ 'status', 'COUNTER', 'c', 'Total Number of Evicted Keys' ],
	 'bgrewriteaof_in_progress' => [ 'status','BOOLEAN', '' ],
	 'expired_keys' => [ 'status', 'COUNTER', 'c', 'Total Number of Expired Keys' ],
	 'used_memory_peak' => [ 'status', 'GAUGE', 'B' ],
	 'connected_slaves' => [ 'status', 'GAUGE', '', 'Number of Connected Slaves' ],
	 'used_cpu_sys_children' => [ 'status', 'GAUGE', '', 'Child Processed Used System CPU' ],
	 'master_host' => [ 'status', 'TEXTINFO', '' ],
	 'master_port' => [ 'status', 'TEXTINFO', '' ],
	 'master_link_status' => [ 'status', 'TEXTINFO', '' ],
	 'slave0' => [ 'status', 'TEXTINFO', '' ],
	 'slave1' => [ 'status', 'TEXTINFO', '' ],
	 'slave2' => [ 'status', 'TEXTINFO', '' ],
	 'slave3' => [ 'status', 'TEXTINFO', '' ],
	);

# Here you can also specify which variables should go into perf data,
# For right now it is 'GAUGE', 'COUNTER', 'DATA' (but not 'TEXTDATA'), and 'BOOLEAN'
# you may want to remove BOOLEAN if you don't want too much data
my $PERF_OK_STATUS_REGEX = 'GAUGE|COUNTER|^DATA$|BOOLEAN';

# ============= MAIN PROGRAM CODE - DO NOT MODIFY BELOW THIS LINE ==============

my $o_host=     undef;		# hostname
my $o_port=     undef;		# port
my $o_pwfile=   undef;          # password file
my $o_password= undef;		# password as parameter
my $o_database= undef;		# database name (usually a number)
my $o_help=     undef;          # help option
my $o_verb=     undef;          # verbose mode
my $o_version=  undef;          # version info option
my $o_variables=undef;          # list of variables for warn and critical
my $o_perfvars= undef;          # list of variables to include in performance data
my $o_warn=     undef;          # warning level option
my $o_crit=     undef;          # Critical level option
my $o_perf=     undef;          # Performance data option
my @o_check=	();		# General check option that maybe repeated more than once
my $o_timeout=  undef;          # Timeout to use - note that normally timeout is from nagios
my $o_timecheck=undef;          # threshold spec for connection time
my $o_memutilization=undef;     # threshold spec for memory utilization%
my $o_totalmemory=undef;	# total memory on a system
my $o_hitrate=  undef;          # threshold spec for hitrate%
my $o_repdelay=undef;           # replication delay time
my @o_querykey=();		# query this key, this option maybe repeated so its an array
my $o_prevperf= undef;		# performance data given with $SERVICEPERFDATA$ macro
my $o_prevtime= undef;		# previous time plugin was run $LASTSERVICECHECK$ macro
my $o_ratelabel=undef;		# prefix and suffix for creating rate variables
my $o_rsuffix='_rate';		# default suffix	
my $o_rprefix='';

## Additional global variables
my $redis= undef;               # DB connection object
my @query=();                   # array of queries with each entry being keyed hash of processedoption data on howto query
my $plugin_cmd = "check_redis.pl";

sub p_version { print "check_redis.pl version : $Version\n"; }

sub print_usage_line {
   print "Usage: $plugin_cmd [-v [debugfilename]] -H <host> [-p <port>] [-x password | -C credentials_file] [-D <database>] [-a <statistics variables> -w <variables warning thresholds> -c <variables critical thresholds>] [-A <performance output variables>] [-T [conntime_warn,conntime_crit]] [-R [hitrate_warn,hitrate_crit]] [-m [mem_utilization_warn,mem_utilization_crit] [-M <maxmemory>[B|K|M|G]]] [-r replication_delay_time_warn,replication_delay_time_crit]  [-f] [-T <timeout>] [-V] [-P <previous performance data in quoted string>] [-q (GET|LLEN|HLEN|SLEN|ZLEN|HGET:name|HEXISTS:name|SEXISTS:name|LRANGE:(AVG|SUM|MIN|MAX):start:end|ZRANGE:(AVG|SUM|MIN|MAX):start:end),query_type,query_key_name[:data_name][,ABSENT:WARNING|CRITICAL][,WARN:threshold,CRIT:threshold]] [-o <threshold specification with name or pattern>]\n";
}

sub print_usage {
   print_usage_line();
   print "For more details on options do: $plugin_cmd --help\n";
}

sub help {
   my $nlib = shift;

   print "Redis Check for Nagios version ",$Version,"\n";
   print " by William Leibzon - william(at)leibzon.org\n\n";
   print "This is redis monitoring plugin to check its stats variables, replication, response time\n";
   print "hitrate, memory utilization and other info. The plugin can also query and test key data\n";
   print "against specified thresholds. All data is available as performance output for graphing.\n\n";
   print_usage_line();
   print "\n";
   print <<EOT;
General and Server Connection Options:
 -v, --verbose[=FILENAME], --debug[=FILENAME]
   Print extra debugging information.
   If filename is specified instead of STDOUT the debug data is written to that file.
 -h, --help
   Print this detailed help screen
 -H, --hostname=ADDRESS
   Hostname or IP Address to check
 -p, --port=INTEGER
   port number (default: 6379)
 -D, --database=NAME
   optional database name (usually a number), needed for --query but otherwise not needed
 -x, --password=STRING
    Password for Redis authentication. Safer alternative is to put them in a file and use -C
 -C, --credentials=FILENAME
    Credentials file to read for Redis authentication
 -t, --timeout=NUMBER
   Allows to set timeout for execution of this plugin. This overrides nagios default.
 -V, --version
   Prints version number

Variables and Thresholds Set as List:
 -a, --variables=STRING[,STRING[,STRING...]]
   List of variables from info data to do threshold checks on.
   The default (if option is not used) is not to monitor any variable.
   The variable name should be prefixed with '&' to chec its rate of
   change over time rather than actual value.
 -w, --warn=STR[,STR[,STR[..]]]
   This option can only be used if '--variables' (or '-a') option above
   is used and number of values listed here must exactly match number
   of variables specified with '-a'. The values specify warning threshold
   for when Nagios should send WARNING alert. These values are usually
   numbers and can have the following prefix modifiers:
      > - warn if data is above this value (default for numeric values)
      < - warn if data is below this value (must be followed by number)
      = - warn if data is equal to this value (default for non-numeric values)
      ! - warn if data is not equal to this value
      ~ - do not check this data (must not be followed by number or ':')
      ^ - for numeric values this disables check that warning < critical
   Threshold values can also be specified as range in two forms:
      num1:num2  - warn if data is outside range i.e. if data<num1 or data>num2
      \@num1:num2 - warn if data is in range i.e. data>=num1 && data<=num2
 -c, --crit=STR[,STR[,STR[..]]]
   This option can only be used if '--variables' (or '-a') option above
   is used and number of values listed here must exactly match number of
   variables specified with '-a'. The values specify critical threshold
   for when Nagios should send CRITICAL alert. The format is exactly same
   as with -w option except no '^' prefix.

Performance Data Processing Options:
 -f, --perfparse
   This should only be used with '-a' and causes variable data not only as part of
   main status line but also as perfparse compatible output (for graphing, etc).
 -A, --perfvars=[STRING[,STRING[,STRING...]]]
   This allows to list variables which values will go only into perfparse
   output (and not for threshold checking). The option by itself (emply value)
   is same as a special value '*' and specify to output all variables.
 -P, --prev_perfdata
   Previous performance data (normally put '-P \$SERVICEPERFDATA\$' in nagios
   command definition). This is used to calculate rate of change for counter
   statistics variables and for proper calculation of hitrate.
 --rate_label=[PREFIX_STRING[,SUFFIX_STRING]]
   Prefix or Suffix label used to create a new variable which has rate of change
   of another base variable. You can specify PREFIX or SUFFIX or both. Default
   if not specified is suffix '_rate' i.e. --rate_label=,_rate

Key Data Query Option (maybe repeated more than once):
 -q, --query=query_type,key[:varname][,ABSENT:OK|WARNING|CRITICAL,WARN:threshold,CRIT:threshold]
   query_type is one of:
	GET          - get one data value
	LLEN         - number of items in a list
	LRANGE:AVG:start:end - retrieve list and average results
	LRANGE:SUM:start:end - retrieve list and sum results
	LRANGE:MIN:start:end - retrieve list and return minimum
	LRANGE:MAX:start:end - retrieve list and return maximum
        HLEN  	     - returns number of items in a hash
        HGET:name    - get specific hash key 'name'
        HEXISTS:name - returns 0 or 1 depending on if specified hash key 'name' exists
        SLEN	     - returns number of items in a set
        SEXISTS:name - returns 0 or 1 depending on if set member 'name' exists
        ZLEN	     - returns number of items in a sorted set
        ZCOUNT:min:max     - counts items in sorted set with scores within the given values
        ZRANGE:AVG:min:max - retrieve sorted set members from min to max and average results
        ZRANGE:SUM:min:max - retrieve sorted set members from min to max and sum results
        ZRANGE:MIN:min:max - retrieve sorted set members from min to max list and return minimum
        ZRANGE:MAX:min:max - retrieve sorted set memers from min to max and return maximum

   Option specifies key to query and optional variable name to assign the results to after :
   (if not specified it would be same as key). If key is not available the plugin can issue
   either warning or critical alert depending on what you specified after ABSENT.
   Numeric results are calculated for ranges and can be checked with specified thresholds
   or you can do it together with standard with redis stats variables and -a option.

General Check Option (all 3 forms equivalent, can be repated more than once):
  -o <list of specifiers>, --option=<list of specifiers>, --check=<list of specifiers>
   where specifiers are separated by , and must include NAME or PATTERN:
     NAME:<string>   - Default name for this variable as you'd have specified with -v
     PATTERN:<regex> - Regular Expression that allows to match multiple data results
     WARN:threshold  - warning alert threshold
     CRIT:threshold  - critical alert threshold
       Threshold is a value (usually numeric) which may have the following prefix:
         > - warn if data is above this value (default for numeric values)
         < - warn if data is below this value (must be followed by number)
         = - warn if data is equal to this value (default for non-numeric values)
         ! - warn if data is not equal to this value
       Threshold can also be specified as a range in two forms:
         num1:num2  - warn if data is outside range i.e. if data<num1 or data>num2
         \@num1:num2 - warn if data is in range i.e. data>=num1 && data<=num2
     ABSENT:OK|WARNING|CRITICAL|UNKNOWN - Nagios alert (or lock of thereof) if data is absent
     ZERO:OK|WARNING|CRITICAL|UNKNOWN   - Nagios alert (or lock of thereof) if result is 0
     DISPLAY:YES|NO - Specifies if data should be included in nagios status line output
     PERF:YES|NO    - Output results as performance data or not (always YES if asked for rate)
     UOM:<string>   - Unit Of Measurement symbol to add to perf data - 'c','%','s','B'

Measured/Calculated Data:
 -T, --response_time=[WARN,CRIT]
   If this is used as just -T the plugin will measure and output connection
   response time in seconds. With -f this would also be provided on perf variables.
   You can also specify values for this parameter, these are interprted as
   WARNING and CRITICAL thresholds (separated by ',').
 -R, --hitrate=[WARN,CRIT]
   Calculates Hitrate %: cache_miss/(cache_hits+cache_miss). If this is used
   as just -R then this info just goes to output line. With '-R -f' these
   go as performance data. You can also specify values for this parameter,
   these are interprted as WARNING and CRITICAL thresholds (separated by ',').
   The format for WARN and CRIT is same as what you would use in -w and -c.
 -m, --memory_utilization=[WARN,CRIT]
   This calculates percent of total memory on system used by redis, which is
      utilization=redis_memory_rss/total_memory*100.
   Total_memory on server must be specified with -M since Redis does not report
   it and can use maximum memory unless you enabled virtual memory and set a limit
   (I plan to test this case and see if it gets reported then).
   If you specify -m by itself, the plugin will just output this info,
   with '-f' it will also include this in performance data. You can also specify
   parameter values which are interpreted as WARNING and CRITICAL thresholds.
 -M, --total_memory=NUM[B|K|M|G]
   Amount of memory on a system for memory utilization calculations above.
   If it does not end with K,M,G then its assumed to be B (bytes)
 -r, --replication_delay=WARN,CRIT
   Allows to set threshold on replication delay info. Only valid if this is a slave!
   The threshold value is in seconds and fractions are acceptable.

EOT

    if (defined($nlib) && $nlib->{'enable_long_options'} == 1) {
	my $long_opt_help = $nlib->additional_options_help();
        if ($long_opt_help) {
	    print "Stats Variable Options (this is alternative to specifying them as list with -a):\n";
	    print $long_opt_help;
	    print "\n";
        }
    }
}

################################ START OF THE LIBRARY FUNCTIONS #####################################
#{
#}
################################# END OF THE LIBRARY FUNCTIONS ######################################

# process --query options (which maybe repeated, that's why loop)
sub option_query {
   my $nlib = shift;

   for(my $i=0;$i<scalar(@o_querykey);$i++) {
	  $nlib->verb("Processing query key option: $o_querykey[$i]");
	  my @ar=split(/,/, $o_querykey[$i]);
	  # how to query
	  my @key_querytype = split(':', uc shift @ar);
	  $nlib->verb("- processing query type specification: ".join(':',@key_querytype));
	  $query[$i] = { 'query_type' => $key_querytype[0] };
	  if ($key_querytype[0] eq 'GET' || $key_querytype[0] eq 'LLEN' ||
	      $key_querytype[0] eq 'SLEN' || $key_querytype[0] eq 'HLEN' ||
	      $key_querytype[0] eq 'ZLEN') {
               if (scalar(@key_querytype)!=1) {
                        print "Incorrect specification. GET, LLEN, SLEN, HLEN, ZLEN do not have any arguments\n";
                        print_usage();
                        exit $ERRORS{"UNKNOWN"};
                }
	  }
	  elsif ($key_querytype[0] eq 'HGET' || $key_querytype[0] eq 'HEXISTS' ||
		 $key_querytype[0] eq 'SEXISTS') {
               if (scalar(@key_querytype)!=2) {
                        print "Incorrect specification of HGET, HEXISTS or SEXIST. Must include hash or set member name as an argument.\n";
                        print_usage();
                        exit $ERRORS{"UNKNOWN"};
                }
                $query[$i]{'element_name'} = $key_querytype[1];
	  }
	  elsif ($key_querytype[0] eq 'LRANGE' || $key_querytype[0] eq 'ZRANGE') {
		if ($key_querytype[0] eq 'ZRANGE' && scalar(@key_querytype)!=4) {
			print "Incorrect specification of ZRANGE. Must include type and start and end (min and max scores).\n";
			print_usage();
			exit $ERRORS{"UNKNOWN"};
		}
                elsif ($key_querytype[0] eq 'LRANGE' && (scalar(@key_querytype)<2 || scalar(@key_querytype)>4)) {
                        print "Incorrect specification of LRANGE. Must include type and start and end range.\n";
                        print_usage();
                        exit $ERRORS{"UNKNOWN"};
                }
		elsif ($key_querytype[1] ne 'MAX' && $key_querytype[1] ne 'MIN' &&
		    $key_querytype[1] ne 'AVG' && $key_querytype[1] ne 'SUM') {
			print "Invalid LRANGE/ZRANGE type $key_querytype[1]. This must be either MAX or MIN or AVG or SUM\n";
			print_usage();
			exit $ERRORS{"UNKNOWN"};
		}
		$query[$i]{'query_subtype'} = $key_querytype[1];
		$query[$i]{'query_range_start'} = $key_querytype[2] if defined($key_querytype[2]);
		$query[$i]{'query_range_end'} = $key_querytype[3] if defined($key_querytype[3]);
	  }
	  else {
		print "Invalid key query $key_querytype[0]. Currently supported are GET, LLEN, SLEN, HLEN, ZLEN, HGET, HEXISTS, SEXISTS,  LRANGE and ZRANGE.\n";
		print_usage();
		exit $ERRORS{"UNKNOWN"};
	  }
	  # key to query and how to name it
	  if (scalar(@ar)==0) {
		print "Invalid query specification. Missing query key name\n";
		print_usage();
		exit $ERRORS{"UNKNOWN"};
	  }
          my ($key_query,$key_name) = split(':', shift @ar);
	  $key_name = $key_query if !defined($key_name) || ! $key_name;
	  $nlib->verb("- variable $key_name will receive data from $key_query");
	  $query[$i]{'key_query'} = $key_query;
	  $query[$i]{'key_name'} = $key_name;
          # parse thresholds and finish processing assigning values to arrays
          my $th = $nlib->parse_thresholds(join(',',@ar));
	  if (exists($th->{'ABSENT'})) {
	      $nlib->verb("- ".$th->{'ABSENT'}." alert will be issued if $key_query is not present");
	      $query[$i]{'alert'} = $th->{'ABSENT'};
	  }
	  if (exists($th->{'WARN'})) {
	      $nlib->verb("- warning threshold ".$th->{'WARN'}." set");
	      $query[$i]{'warn'} = $th->{'WARN'};
	  }
	  if (exists($th->{'CRIT'})) {
	      $nlib->verb("- critical threshold ".$th->{'CRIT'}." set");
	      $query[$i]{'crit'} = $th->{'CRIT'};
	  }
	  $nlib->add_threshold($key_name,$th);
     }
}

# sets password, host, port and other data based on options entered
sub options_setaccess {
    if (!defined($o_host)) { print "Please specify hostname (-H)\n"; print_usage(); exit $ERRORS{"UNKNOWN"}; }
    if (defined($o_pwfile) && $o_pwfile) {
        if ($o_password) {
	    print "use either -x or -C to enter credentials\n"; print_usage(); exit $ERRORS{"UNKNOWN"};
	}
        open my $file, '<', $o_pwfile or die $!;
        while (<$file>) {
            # Match first non-blank line that doesn't start with a comment
            if (!($_ =~ /^\s*#/) && $_ =~ /\S+/) {
                chomp($PASSWORD = $_);
                last;
            }
        }
        close $file;
        print 'Password file is empty' and exit $ERRORS{"UNKNOWN"} if !$PASSWORD;
    }
    if (defined($o_password) && $o_password) {
	$PASSWORD = $o_password;
    }
    $HOSTNAME = $o_host if defined($o_host);
    $PORT     = $o_port if defined($o_port);
    $TIMEOUT  = $o_timeout if defined($o_timeout);
    $DATABASE = $o_database if defined($o_database);
}

# parse command line options
sub check_options {
    my $opt;
    my $nlib = shift;
    my %Options = ();
    Getopt::Long::Configure("bundling");
    GetOptions(\%Options,
   	'v:s'	=> \$o_verb,		'verbose:s' => \$o_verb, "debug:s" => \$o_verb,
        'h'     => \$o_help,            'help'          => \$o_help,
        'H:s'   => \$o_host,            'hostname:s'    => \$o_host,
        'p:i'   => \$o_port,            'port:i'        => \$o_port,
        'C:s'   => \$o_pwfile,          'credentials:s' => \$o_pwfile,
        'x:s'   => \$o_password,	'password:s'	=> \$o_password,
	'D:s'	=> \$o_database,	'database:s'	=> \$o_database,
        't:i'   => \$o_timeout,         'timeout:i'     => \$o_timeout,
        'V'     => \$o_version,         'version'       => \$o_version,
	'a:s'   => \$o_variables,       'variables:s'   => \$o_variables,
        'c:s'   => \$o_crit,            'critical:s'    => \$o_crit,
        'w:s'   => \$o_warn,            'warn:s'        => \$o_warn,
	'f:s'   => \$o_perf,            'perfparse:s'   => \$o_perf,
	'A:s'   => \$o_perfvars,        'perfvars:s'    => \$o_perfvars,
        'T:s'   => \$o_timecheck,       'response_time:s' => \$o_timecheck,
        'R:s'   => \$o_hitrate,         'hitrate:s'     => \$o_hitrate,
        'r:s'   => \$o_repdelay,        'replication_delay:s' => \$o_repdelay,
        'P:s'   => \$o_prevperf,        'prev_perfdata:s' => \$o_prevperf,
        'E:s'   => \$o_prevtime,        'prev_checktime:s'=> \$o_prevtime,
        'm:s'   => \$o_memutilization,  'memory_utilization:s' => \$o_memutilization,
	'M:s'	=> \$o_totalmemory,	'total_memory:s' => \$o_totalmemory,
	'q=s'	=> \@o_querykey,	'query=s'	 => \@o_querykey,
	'o=s'	=> \@o_check,		'check|option=s' => \@o_check,
	'rate_label:s'	=> \$o_ratelabel,
	map { ($_) } $nlib->additional_options_list()
    );

    ($o_rprefix,$o_rsuffix)=split(/,/,$o_ratelabel) if defined($o_ratelabel) && $o_ratelabel ne '';

    # Standard nagios plugin required options
    if (defined($o_help)) { help($nlib); exit $ERRORS{"UNKNOWN"} };
    if (defined($o_version)) { p_version(); exit $ERRORS{"UNKNOWN"} };

    # now start options processing in the library
    $nlib->options_startprocessing(\%Options, $o_verb, $o_variables, $o_warn, $o_crit, $o_perf, $o_perfvars, $o_rprefix, $o_rsuffix);

    # additional variables/options calculated and added by this plugin
    if (defined($o_timecheck) && $o_timecheck ne '') {
          $nlib->verb("Processing timecheck thresholds: $o_timecheck");
	  $nlib->add_threshold('response_time',$o_timecheck);
    }
    if (defined($o_hitrate) && $o_hitrate ne '') {
          $nlib->verb("Processing hitrate thresholds: $o_hitrate");
	  $nlib->add_threshold('hitrate',$o_hitrate);
	  $nlib->set_threshold('hitrate','ZERO','OK') if !defined($nlib->get_threshold('hitrate','ZERO')); # except case of hitrate=0, don't remember why I added it
    }
    if (defined($o_memutilization) && $o_memutilization ne '') {
          $nlib->verb("Processing memory utilization thresholds: $o_memutilization");
          $nlib->add_threshold('memory_utilization',$o_memutilization);
    }
    if (defined($o_totalmemory)) {
	if ($o_totalmemory =~ /^(\d+)B/) {
	   $o_totalmemory = $1;
	}
	elsif ($o_totalmemory =~ /^(\d+)K/) {
	   $o_totalmemory = $1*1024;
	}
	elsif ($o_totalmemory =~ /^(\d+)M/) {
	   $o_totalmemory = $1*1024*1024;
	}
	elsif ($o_totalmemory =~ /^(\d+)G/) {
	   $o_totalmemory = $1*1024*1024*1024;
	}
	elsif ($o_totalmemory !~ /^(\d+)$/) {
		print "Total memory value $o_totalmemory can not be interpreted\n";
		print_usage();
		exit $ERRORS{"UNKNOWN"};
	}
    }
    if (defined($o_repdelay) && $o_repdelay ne '') {
          $nlib->verb("Processing replication delay thresholds: $o_repdelay");
          $nlib->add_threshold('replication_delay',$o_repdelay);
    }

    # general check option, allows to specify everything, can be repeated more than once
    foreach $opt (@o_check) {
	  $nlib->verb("Processing general check option: ".$opt);
	  $nlib->add_threshold(undef,$opt);
    }

    # query option processing
    option_query($nlib);

    # finish it up
    $nlib->options_finishprocessing();
    options_setaccess();
}

# Get the alarm signal (just in case nagios screws up)
$SIG{'ALRM'} = sub {
     $redis->quit if defined($redis);
     print ("ERROR: Alarm signal (Nagios time-out)\n");
     exit $ERRORS{"UNKNOWN"};
};

########## MAIN #######

my $nlib = Naglio->lib_init('plugin_name' => 'check_redis.pl',
			    'plugins_authors' => 'William Leibzon',
			    'plugin_description' => 'Redis Monitoring Plugin for Nagios',
			    'usage_function' => \&print_usage,
                            'enable_long_options' => 1,
                            'enable_rate_of_change' => 1);
$nlib->set_knownvars(\%KNOWN_STATUS_VARS, $PERF_OK_STATUS_REGEX);

check_options($nlib);
$nlib->verb("check_redis.pl plugin version ".$Version);

# Check global timeout if plugin screws up
if (defined($TIMEOUT)) {
  $nlib->verb("Alarm at $TIMEOUT");
  alarm($TIMEOUT);
}
else {
  $nlib->verb("no timeout defined : $o_timeout + 10");
  alarm ($o_timeout+10);
}

# some more variables for processing of the results
my $dbversion = "";
my $vnam;
my $vval;
my %dbs=();	# database-specific info, this is almost unused right now
my %slaves=();
my $avar;

# connect using tcp and verify the port is working
my $sock = new IO::Socket::INET(
  PeerAddr => $HOSTNAME,
  PeerPort => $PORT,
  Proto => 'tcp',
);
if (!$sock) {
  print "CRITICAL ERROR - Can not connect to '$HOSTNAME' on port $PORT\n";
  exit $ERRORS{'CRITICAL'};
}
close($sock);

# now do connection using Redis library
my $start_time;
my $dsn = $HOSTNAME.":".$PORT;
$nlib->verb("connecting to $dsn");
$start_time = [ Time::HiRes::gettimeofday() ] if defined($o_timecheck);

$redis = Redis-> new ( server => $dsn, 'debug' => (defined($o_verb))?1:0 );

if ($PASSWORD) {
    $redis->auth($PASSWORD);
}
if ($DATABASE) {
    $redis->select($DATABASE);
}

if (!$redis) {
  print "CRITICAL ERROR - Redis Library - can not connect to '$HOSTNAME' on port $PORT\n";
  exit $ERRORS{'CRITICAL'};
}

if (!$redis->ping) {
  print "CRITICAL ERROR - Redis Library - can not ping '$HOSTNAME' on port $PORT\n";
  exit $ERRORS{'CRITICAL'};
}

# This returns hashref of various statistics/info data
my $stats = $redis->info();

# Check specified key if option -q was used
for (my $i=0; $i<scalar(@query);$i++) {
  my $result=undef;
  if ($query[$i]{'query_type'} eq 'GET') {
	$nlib->verb("Getting redis key: ".$query[$i]{'key_query'});
  	$result = $redis->get($query[$i]{'key_query'});
  }
  elsif ($query[$i]{'query_type'} eq 'LLEN') {
	$nlib->verb("Getting number of items for list with redis key: ".$query[$i]{'key_query'});
  	$result = $redis->llen($query[$i]{'key_query'});
  }
  elsif ($query[$i]{'query_type'} eq 'HLEN') {
        $nlib->verb("Getting number of items for hash with redis key: ".$query[$i]{'key_query'});
        $result = $redis->hlen($query[$i]{'key_query'});
  }
  elsif ($query[$i]{'query_type'} eq 'SLEN') {
        $nlib->verb("Getting number of items for set with redis key: ".$query[$i]{'key_query'});
        $result = $redis->scard($query[$i]{'key_query'});
  }
  elsif ($query[$i]{'query_type'} eq 'ZLEN') {
        $nlib->verb("Getting number of items for sorted set with redis key: ".$query[$i]{'key_query'});
        $result = $redis->zcard($query[$i]{'key_query'});
  }
  elsif ($query[$i]{'query_type'} eq 'HGET') {
        $nlib->verb("Getting hash member ".$query[$i]{'element_name'}." with redis key: ".$query[$i]{'key_query'});
        $result = $redis->hget($query[$i]{'key_query'},$query[$i]{'element_name'});
  }
  elsif ($query[$i]{'query_type'} eq 'HEXISTS') {
        $nlib->verb("Checking if there exists hash member ".$query[$i]{'element_name'}." with redis key: ".$query[$i]{'key_query'});
        $result = $redis->hexists($query[$i]{'key_query'},$query[$i]{'element_name'});
  }
  elsif ($query[$i]{'query_type'} eq 'SEXISTS') {
        $nlib->verb("Checking if there exists set member ".$query[$i]{'element_name'}." with redis key: ".$query[$i]{'key_query'});
        $result = $redis->sismember($query[$i]{'key_query'},$query[$i]{'element_name'});
  }
  elsif ($query[$i]{'query_type'} eq 'LRANGE' || $query[$i]{'query_type'} eq 'ZRANGE') {
	my $range_start;
	my $range_end;
	if (defined($query[$i]{'query_range_start'}) && $query[$i]{'query_range_start'} ne '') {
	    $range_start=$query[$i]{'query_range_start'};
	}
        else {
	    $range_start=0;
	}
	if (defined($query[$i]{'query_range_end'}) && $query[$i]{'query_range_end'} ne '') {
	    $range_end= $query[$i]{'query_range_end'};
	}
	elsif ($query[$i]{'query_type'} eq 'LRANGE') {
	    $nlib->verb("Getting (lrange) redis key: ".$query[$i]{'key_query'});
	    $range_end = $redis->llen($query[$i]{'key_query'})-1;
	}
	else {
	    print "ERROR - can not do ZRANGE if you do not specify mix and max score.";
	    exit $ERRORS{"UNKNOWN"};
	}
	my @list;
	if ($query[$i]{'query_type'} eq 'LRANGE') {
	   @list = $redis->lrange($query[$i]{'key_query'}, $range_start, $range_end);
	}
	else {
	   @list = $redis->zrange($query[$i]{'key_query'}, $range_start, $range_end);
	}
	if (scalar(@list)>0) {
		$result=shift @list;
		foreach(@list) {
		    $result+=$_ if $query[$i]{'query_subtype'} eq 'SUM' || $query[$i]{'query_subtype'} eq 'AVG';
		    $result=$_ if ($query[$i]{'query_subtype'} eq 'MIN' && $_ < $result) ||
				  ($query[$i]{'query_subtype'} eq 'MAX' && $_ > $result);
		}
		$result = $result / (scalar(@list)+1) if $query[$i]{'query_subtype'} eq 'AVG';
	}
  }
  if (defined($result)) {
      $query[$i]{'result'} = $result;
      $nlib->add_data($query[$i]{'key_name'}, $result);
      $nlib->verb("Result of querying ".$query[$i]{'key_query'}." is: $result");
  }
  else {
      $nlib->verb("could not get results for ".$query[$i]{'key_query'});
  }
  # else {
  #    if (exists($query[$i]{'alert'}) && $query[$i]{'alert'} ne 'OK') {
  #	$statuscode=$query[$i]{'alert'} if $statuscode ne 'CRITICAL';
  #	$statusinfo.=", " if $statusinfo;
  #	$statusinfo.= "Query on ".$query[$i]{'key_query'}." did not succeed";
  #    }
  # }
}

# end redis session
$redis->quit;

# load stats data into internal hash array
my $total_keys=0;
my $total_expires=0;
foreach $vnam (keys %{$stats}) {
     $vval = $stats->{$vnam};
     if (defined($vval)) {
    	$nlib->verb("Stats Line: $vnam = $vval");
	if (exists($KNOWN_STATUS_VARS{$vnam}) && $KNOWN_STATUS_VARS{$vnam}[1] eq 'VERSION') {
		$dbversion .= $vval;
	}
	elsif ($vnam =~ /^db\d+$/) {
		$dbs{$vnam}= {'name'=>$vnam};
		foreach (split(/,/,$vval)) {
			my ($k,$d) = split(/=/,$_);
			$nlib->add_data($vnam.'_'.$k,$d);
			$dbs{$vnam}{$k}=$d;
			$nlib->verb(" - stats data added: ".$vnam.'_'.$k.' = '.$d);
			$total_keys+=$d if $k eq 'keys' && Naglio::isnum($d);
			$total_expires+=$d if $k eq 'expires' && Naglio::isnum($d);
		}
	}
	elsif ($vnam =~ /~slave/) {
		# TODO TODO TODO TODO
	}
	else {
		$nlib->add_data($vnam, $vval);
   	}
     }
     else {
        $nlib->verb("Stats Data: $vnam = NULL");
     }
}
$nlib->verb("Calculated Data: total_keys=".$total_keys);
$nlib->verb("Calculated Data: total_expires=".$total_expires);
$nlib->add_data('total_keys',$total_keys);
$nlib->add_data('total_expires',$total_expires);

# Response Time
if (defined($o_timecheck)) {
    $nlib->add_data('response_time',Time::HiRes::tv_interval($start_time));
    $nlib->addto_statusdata_output('response_time',sprintf("response in %.3fs",$nlib->vardata('response_time')));
    if (defined($o_perf)) {
        $nlib->set_perfdata('response_time','response_time='.$nlib->vardata('response_time'),'s');
    }
}

# calculate rate variables
$nlib->calculate_ratevars();

# Hitrate
my $hitrate=0;
my $hits_total=0;
my $hits_hits=undef;
my $hitrate_all=0;
if (defined($o_hitrate) && defined($nlib->vardata('keyspace_hits')) && defined($nlib->vardata('keyspace_misses'))) {
    for $avar ('keyspace_hits', 'keyspace_misses') {
        if (defined($o_prevperf) && defined($o_perf)) {
                $nlib->set_perfdata($avar,$avar."=".$nlib->vardata($avar),'c');
        }
        $hits_hits = $nlib->vardata('keyspace_hits') if $avar eq 'keyspace_hits';
        $hits_total += $nlib->vardata($avar);
    }
    $nlib->verb("Calculating Hitrate : total=".$hits_total." hits=".$hits_hits);
    if (defined($hits_hits) && defined($nlib->prev_perf('keyspace_hits')) && defined($nlib->prev_perf('keyspace_misses')) && $hits_hits > $nlib->prev_perf('keyspace_hits')) {
        $hitrate_all = $hits_hits/$hits_total*100 if $hits_total!=0;
        $hits_hits -= $nlib->prev_perf('keyspace_hits');
        $hits_total -= $nlib->prev_perf('keyspace_misses');
        $hits_total -= $nlib->prev_perf('keyspace_hits');
        verb("Calculating Hitrate. Adjusted based on previous values. total=".$hits_total." hits=".$hits_hits);
    }
    if (defined($hits_hits)) {
    	if ($hits_total!=0) {
	    $hitrate= sprintf("%.4f", $hits_hits/$hits_total*100);
	}
	$nlib->add_data('hitrate',$hitrate);
	my $sdata .= sprintf(" hitrate is %.2f%%", $hitrate);
	$sdata .= sprintf(" (%.2f%% from launch)", $hitrate_all) if ($hitrate_all!=0);
	$nlib->addto_statusdata_output('hitrate',$sdata);
	if (defined($o_perf)) {
		$nlib->set_perfdata('hitrate',"hitrate=$hitrate",'%');
	}
     }
}

# Replication Delay
my $repl_delay=0;
if (defined($o_repdelay) && defined($nlib->vardata('master_last_io_seconds_ago')) && defined($nlib->vardata('role'))) {
    if ($nlib->vardata('role') eq 'slave') {
	$repl_delay = $nlib->vardata('master_link_down_since_seconds');
	if (!defined($repl_delay) || $repl_delay < $nlib->vardata('master_last_io_seconds_ago')) {
	    $repl_delay = $nlib->vardata('master_last_io_seconds_ago','s');
	}
	if (defined($repl_delay) && $repl_delay>=0) {
	    $nlib->add_data('replication_delay',$repl_delay);
	    $nlib->addto_statusdata_output('replication_delay',sprintf("replication_delay is %d", $nlib->vardata('replication_delay')));
	    if (defined($o_perf)) {
		$nlib->set_perfdata('replication_delay',sprintf("replication_delay=%d", $nlib->vardata('replication_delay')));
	    }
	}
    }
}

# Memory Use Utilization
if (defined($o_memutilization) && defined($nlib->vardata('used_memory_rss'))) {
    if (defined($o_totalmemory)) {
        $nlib->add_data('memory_utilization',$nlib->vardata('used_memory_rss')/$o_totalmemory*100);
	$nlib->verb('memory utilization % : '.$nlib->vardata('memory_utilization').' = '.$nlib->vardata('used_memory_rss').' (used_memory_rss) / '.$o_totalmemory.' * 100');
    }
    elsif ($o_memutilization ne '') {
	print "ERROR: Can not calculate memory utilization if you do not specify total memory on a system (-M option)\n";
	print_usage();
	exit $ERRORS{"UNKNOWN"};
    }
    if (defined($o_perf) && defined($nlib->vardata('memory_utilization'))) {
	$nlib->set_perfdata('memory_utilization',sprintf(" memory_utilization=%.4f", $nlib->vardata('memory_utilization')),'%');
    }
    if (defined($nlib->vardata('used_memory_human')) && defined($nlib->vardata('used_memory_peak_human'))) {
	my $sdata="memory use is ".$nlib->vardata('used_memory_human')." (";
	$sdata.='peak '.$nlib->vardata('used_memory_peak_human');
	if (defined($nlib->vardata('memory_utilization'))) {
		$sdata.= sprintf(", %.2f%% of max", $nlib->vardata('memory_utilization'));
	}
	if (defined($nlib->vardata('mem_fragmentation_ratio'))) {
		$sdata.=", fragmentation ".$nlib->vardata('mem_fragmentation_ratio').'%';
	}
	$sdata.=")";
	$nlib->addto_statusdata_output('memory_utilization',$sdata);
    }
}

# Check thresholds in all variables and prepare status and performance data for output
$nlib->main_checkvars();
$nlib->main_perfvars();

# now output the results
print $nlib->statuscode() . ': '.$nlib->statusinfo();
print " - " if $nlib->statusinfo();
print "REDIS " . $dbversion . ' on ' . $HOSTNAME. ':'. $PORT;
print ' has '.scalar(keys %dbs).' databases ('.join(',',keys(%dbs)).')';
print " with $total_keys keys" if $total_keys > 0;
print ', up '.$nlib->readable_time($nlib->vardata('uptime_in_seconds')) if defined($nlib->vardata('uptime_in_seconds'));
print " - " . $nlib->statusdata() if $nlib->statusdata();
print $nlib->perfdata();
print "\n";

# end exit
exit $ERRORS{$nlib->statuscode()};
