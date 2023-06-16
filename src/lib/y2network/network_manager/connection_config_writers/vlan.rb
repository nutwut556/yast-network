# Copyright (c) [2021] SUSE LLC
#
# All Rights Reserved.
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of version 2 of the GNU General Public License as published
# by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
# FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
# more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, contact SUSE LLC.
#
# To contact SUSE LLC about this file by physical or electronic mail, you may
# find current contact information at www.suse.com.

require "y2network/network_manager/connection_config_writers/base"

module Y2Network
  module NetworkManager
    module ConnectionConfigWriters
      # This class is responsible for writing the information from a ConnectionConfig::Vlan
      # object to the underlying system.
      class Vlan < Base
        # @see Y2Network::ConnectionConfigWriters::Base#update_file
        # @param conn [Y2Network::ConnectionConfig::Vlan] Configuration to write
        def update_file(conn)
          file.vlan["id"] = conn.vlan_id.to_s
          file.vlan["parent"] = conn.parent_device
          file.vlan["type"] = "vlan"
        end
      end
    end
  end
end
