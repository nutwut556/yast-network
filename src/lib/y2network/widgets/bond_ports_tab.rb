# Copyright (c) [2019] SUSE LLC
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

require "yast"
require "cwm/tabs"

# used widgets
require "y2network/widgets/bond_port"
require "y2network/widgets/bond_options"

module Y2Network
  module Widgets
    class BondPortsTab < CWM::Tab
      def initialize(settings)
        super()
        textdomain "network"

        @settings = settings
      end

      def label
        _("&Bond Ports")
      end

      def contents
        VBox(BondPort.new(@settings), BondOptions.new(@settings))
      end
    end
  end
end
