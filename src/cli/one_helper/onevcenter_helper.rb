
# -------------------------------------------------------------------------- #
# Copyright 2002-2018, OpenNebula Project, OpenNebula Systems                #
#                                                                            #
# Licensed under the Apache License, Version 2.0 (the "License"); you may    #
# not use this file except in compliance with the License. You may obtain    #
# a copy of the License at                                                   #
#                                                                            #
# http://www.apache.org/licenses/LICENSE-2.0                                 #
#                                                                            #
# Unless required by applicable law or agreed to in writing, software        #
# distributed under the License is distributed on an "AS IS" BASIS,          #
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.   #
# See the License for the specific language governing permissions and        #
# limitations under the License.                                             #
#--------------------------------------------------------------------------- #

require 'one_helper'

class OneVcenterHelper < OpenNebulaHelper::OneHelper

    module VOBJECT
      DATASTORE = 1
      TEMPLATE = 2
      NETWORK = 3
      IMAGE = 4
    end

    TABLE = {
        VOBJECT::DATASTORE => {
            :struct  => ["DATASTORE_LIST", "DATASTORE"],
            :columns => {:IMID => 5, :REF => 15, :NAME => 25, :CLUSTERS => 10},
            :cli     => [:host],
            :dialogue => ->(arg){}
        },
        VOBJECT::TEMPLATE => {
            :struct  => ["TEMPLATE_LIST", "TEMPLATE"],
            :columns => {:IMID => 5, :REF => 10, :NAME => 35},
            :cli     => [:host],
            :dialogue => ->(arg){ OneVcenterHelper.template_dialogue(arg) }
        },
        VOBJECT::NETWORK => {
            :struct  => ["NETWORK_LIST", "NETWORK"],
            :columns => {:IMID => 5, :REF => 15, :NAME => 10},
            :cli     => [:host],
            :dialogue => ->(arg){ OneVcenterHelper.network_dialogue(arg) }
        },
        VOBJECT::IMAGE => {
            :struct  => ["IMAGE_LIST", "IMAGE"],
            :columns => {:IMID => 5,:REF => 20, :PATH => 20},
            :cli     => [:host, :datastore],
            :dialogue => ->(arg){}
        }
    }


    #######################
    # CLI ARGS
    ########################
    def datastore(arg)
        ds = VCenterDriver::VIHelper.one_item(OpenNebula::Datastore, arg)

        {
            ds_ref: ds['TEMPLATE/VCENTER_DS_REF'],
            one_item: ds
        }
    end

    def host(arg)
    end
    ########################


    def show_header(vcenter_host)
        CLIHelper.scr_bold
        CLIHelper.scr_underline
        puts "# vCenter: #{vcenter_host}".ljust(50)
        CLIHelper.scr_restore
        puts

    end

    def set_object(type)
        type = type.downcase
        if (type == "datastores")
            @vobject = VOBJECT::DATASTORE
        elsif (type == "templates")
            @vobject = VOBJECT::TEMPLATE
        elsif (type =="networks")
            @vobject = VOBJECT::NETWORK
        elsif (type == "images")
            @vobject = VOBJECT::IMAGE
        end
    end

    def connection_options(object_name, options)
        if  options[:vuser].nil? || options[:vcenter].nil?
            raise "vCenter connection parameters are mandatory to import"\
                  " #{object_name}:\n"\
                  "\t --vcenter vCenter hostname\n"\
                  "\t --vuser username to login in vcenter"
        end

        password = options[:vpass] || OpenNebulaHelper::OneHelper.get_password
        {
           :user     => options[:vuser],
           :password => password,
           :host     => options[:vcenter]
        }
    end

    def cli_format( hash)
        {TABLE[@vobject][:struct].first => {TABLE[@vobject][:struct].last => hash.values}}
    end

    def list_object(options, list)
        vcenter_host = list.keys[0]
        list = cli_format(list.values.first)
        table = format_list()

        show_header(vcenter_host)

        table.show(list)
    end

    def cli_dialogue(object_info)
        return TABLE[@vobject][:dialogue].(object_info)
    end

    def parse_opts(opts)
        set_object(opts[:object])

        res = {}
        TABLE[@vobject][:cli].each do |arg|
            raise "#{arg} it's mandadory for this op" if opts[arg].nil?
            res[arg] = self.method(arg).call(opts[arg])
        end


        return res
    end

    def format_list()
        config = TABLE[@vobject][:columns]
        table = CLIHelper::ShowTable.new() do
            column :IMID, "identifier for ...", :size=>config[:IMID] || 4 do |d|
                d[:import_id]
            end

            column :REF, "ref", :left, :size=>config[:REF] || 15 do |d|
                d[:ref]
            end

            column :NAME, "Name", :left, :size=>config[:NAME] || 20 do |d|
                d[:name] || d[:simple_name]
            end

            column :CLUSTERS, "CLUSTERS", :left, :size=>config[:CLUSTERS] || 10 do |d|
                d[:cluster].to_s || d[:clusters][:one_ids].to_s
            end

            column :PATH, "PATH", :left, :size=>config[:PATH] || 10 do |d|
                d[:path]
            end

            default(*config.keys)
        end

        table
    end

    def self.template_dialogue(t)
        rps_list = -> {
            return "" if t[:rp_list].empty?
            puts
            t[:rp_list].each do |rp|
                puts "      #{rp[:name]}"
            end
            puts

            return STDIN.gets.strip.downcase
        }

        # default opts
        opts = {
            linked_clone: '0',
            copy: '0',
            name: '',
            folder: '',
            resourcepool: [],
            type: ''
        }

        # LINKED CLONE OPTION
        STDOUT.print "\n    For faster deployment operations"\
                     " and lower disk usage, OpenNebula"\
                     " can create new VMs as linked clones."\
                     "\n    Would you like to use Linked Clones with VMs based on this template (y/[n])? "

        if STDIN.gets.strip.downcase == 'y'
            opts[:linked_clone] = '1'


            # CREATE COPY OPTION
            STDOUT.print "\n    Linked clones requires that delta"\
                         " disks must be created for each disk in the template."\
                         " This operation may change the template contents."\
                         " \n    Do you want OpenNebula to create a copy of the template,"\
                         " so the original template remains untouched ([y]/n)? "

            if STDIN.gets.strip.downcase != 'n'
                opts[:copy] = '1'

                # NAME OPTION
                STDOUT.print "\n    The new template will be named"\
                             " adding a one- prefix to the name"\
                             " of the original template. \n"\
                             "    If you prefer a different name"\
                             " please specify or press Enter"\
                             " to use defaults: "

                template_name = STDIN.gets.strip.downcase
                opts[:name] = template_name

                STDOUT.print "\n    WARNING!!! The cloning operation can take some time"\
                             " depending on the size of disks.\n"
            end
        end

        STDOUT.print "\n\n    Do you want to specify a folder where"\
                        " the deployed VMs based on this template will appear"\
                        " in vSphere's VM and Templates section?"\
                        "\n    If no path is set, VMs will be placed in the same"\
                        " location where the template lives."\
                        "\n    Please specify a path using slashes to separate folders"\
                        " e.g /Management/VMs or press Enter to use defaults: "\

        vcenter_vm_folder = STDIN.gets.strip
        opts[:folder] = vcenter_vm_folder

        STDOUT.print "\n\n    This template is currently set to "\
            "launch VMs in the default resource pool."\
            "\n    Press y to keep this behaviour, n to select"\
            " a new resource pool or d to delegate the choice"\
            " to the user ([y]/n/d)? "

        answer =  STDIN.gets.strip.downcase

        case answer.downcase
        when 'd' || 'delegate'
            opts[:type]='list'
            puts "separate with commas ',' the list that you want to deleate:"

            opts[:resourcepool] = rps_list.call.gsub(/\s+/, "").split(",")

        when 'n' || 'no'
            opts[:type]='fixed'
            puts "choose the proper name"
            opts[:resourcepool] = rps_list.call
        else
            opts[:type]='default'
        end

        return opts
    end

    def self.network_dialogue(n)
        ask = -> (question, default = ""){
            STDOUT.print question
            answer = STDIN.gets.strip

            answer = default if answer.empty?

            return answer
        }

        opts = { size: "255", type: "ether" }

		question =  "    How many VMs are you planning"\
					" to fit into this network [255]? "
        opts[:size] = ask.call(question, "255")

		question = "    What type of Virtual Network"\
				   " do you want to create (IPv[4],IPv[6], [E]thernet)?"
        type_answer = ask.call(question, "ether")

        supported_types = ["4","6","ether", "e", "ip4", "ip6" ]
        if !supported_types.include?(type_answer)
            type_answer =  'e'
			STDOUT.puts "    Type [#{type_answer}] not supported,"\
						" defaulting to Ethernet."
        end
        question_ip  = "    Please input the first IP in the range: "
        question_mac = "    Please input the first MAC in the range [Enter for default]: "

        case type_answer.downcase
		when "4", "ip4"
			opts[:ip]  = ask.call(question_ip)
			opts[:mac] = ask.call(question_mac)
            opts[:type] = "ip"
		when "6", "ip6"
			opts[:mac] = ask.call(question_mac)

			question =   "    Do you want to use SLAAC "\
						 "Stateless Address Autoconfiguration? ([y]/n): "
            slaac_answer = ask.call(question, 'y').downcase

			if slaac_answer == 'n'
				question =  "    Please input the IPv6 address (cannot be empty): "
				opts[:ip6] = ask.call(question)

				question =  "    Please input the Prefix length (cannot be empty): "
				opts[:prefix_length] = ask.call(question)
                opts[:type] = 'ip6_static'
			else
				question =  "    Please input the GLOBAL PREFIX "\
							"[Enter for default]: "
				opts[:global_prefix] = ask.call(question)

				question=  "    Please input the ULA PREFIX "\
						   "[Enter for default]: "
				opts[:ula_prefix] = ask.call(question)
                opts[:type]       = 'ip6'
			end
		when "e", "ether"
			opts[:mac] = ask.call(question_mac)
		end

        return opts
    end
end
