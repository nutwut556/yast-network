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

require "cwm/common_widgets"
require "y2network/wireless_mode"

module Y2Network
  module Widgets
    # Widget to select mode in which wifi card operate
    class WirelessMode < CWM::ComboBox
      # @param config [Y2network::InterfaceConfigBuilder]
      def initialize(config)
        super()
        @config = config
        textdomain "network"
      end

      def label
        _("O&perating Mode")
      end

      def init
        self.value = @config.mode
      end

      # notify when mode change as it affect other elements
      def opt
        [:notify, :hstretch]
      end

      def store
        @config.mode = value
      end

      def items
        Y2Network::WirelessMode.all.map { |m| [m.short_name, m.to_human_string] }
      end
    end
  end
end
