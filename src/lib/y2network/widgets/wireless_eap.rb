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

require "cwm/custom_widget"
require "cwm/replace_point"

require "y2network/widgets/wireless_eap_mode"
require "y2network/widgets/server_ca_path"
require "y2network/widgets/client_cert_path"
require "y2network/widgets/client_key"

module Y2Network
  module Widgets
    # High Level widget that allow to select kind of EAP authentication and also dynamically change
    # its content according to the selection
    class WirelessEap < CWM::CustomWidget
      attr_reader :settings

      def initialize(settings)
        @settings = settings
        self.handle_all_events = true
      end

      def init
        eap_mode.init
        refresh
      end

      def handle(event)
        return if event["ID"] != eap_mode.widget_id

        refresh
        nil
      end

      def contents
        VBox(
          HStretch(),
          eap_mode,
          VSpacing(0.2),
          replace_widget
        )
      end

    private

      def eap_mode
        @eap_mode ||= WirelessEapMode.new(settings)
      end

      def replace_widget
        @replace_widget ||= CWM::ReplacePoint.new(id:     "wireless_eap_point",
          widget: CWM::Empty.new("wireless_eap_empty"))
      end

      def refresh
        case eap_mode.value
        when "TTLS" then replace_widget.replace(ttls_widget)
        when "PEAP" then replace_widget.replace(peap_widget)
        when "TLS" then replace_widget.replace(tls_widget)
        else raise "unknown value #{eap_mode.value.inspect}"
        end
      end

      def ttls_widget
        @ttls_widget ||= EapTtls.new(@settings)
      end

      def peap_widget
        @peap_widget ||= EapPeap.new(@settings)
      end

      def tls_widget
        @tls_widget ||= EapTls.new(@settings)
      end
    end

    # High level widget that represent PEAP authentication
    class EapPeap < CWM::CustomWidget
      attr_reader :settings

      def initialize(settings)
        @settings = settings
      end

      def contents
        VBox(
          HBox(EapUser.new(@settings), HSpacing(1), EapPassword.new(@settings)),
          ServerCAPath.new(@settings)
        )
      end
    end

    # High level widget that represent TTLS authentication
    class EapTtls < CWM::CustomWidget
      attr_reader :settings

      def initialize(settings)
        @settings = settings
      end

      def contents
        VBox(
          HBox(EapUser.new(@settings), HSpacing(1), EapPassword.new(@settings)),
          EapAnonymousUser.new(@settings),
          ServerCAPath.new(@settings)
        )
      end
    end

    # High level widget that represent TLS authentication
    class EapTls < CWM::CustomWidget
      attr_reader :settings

      def initialize(settings)
        @settings = settings
      end

      def contents
        VBox(
          HStretch(),
          EapUser.new(@settings),
          ClientCertPath.new(@settings),
          HBox(
            ClientKeyPath.new(@settings),
            HSpacing(1),
            ClientKeyPassword.new(@settings)
          ),
          ServerCAPath.new(@settings)
        )
      end
    end

    # Widget that represent EAP password
    class EapPassword < CWM::Password
      def initialize(builder)
        @builder = builder
        textdomain "network"
      end

      def label
        _("Password")
      end

      def opt
        [:hstretch]
      end

      def init
        self.value = @builder.wpa_password
      end

      def store
        @builder.wpa_password = value
      end

      def help
        "" # TODO: write it
      end
    end

    # Widget that represent EAP user
    class EapUser < CWM::InputField
      def initialize(builder)
        @builder = builder
        textdomain "network"
      end

      def label
        _("Identity")
      end

      def init
        self.value = @builder.wpa_identity
      end

      def store
        @builder.wpa_identity = value
      end

      def help
        "" # TODO: write it
      end
    end

    # Widget that represent EAP anonymous user that is used for initial connection
    class EapAnonymousUser < CWM::InputField
      def initialize(builder)
        @builder = builder
        textdomain "network"
      end

      def label
        _("&Anonymous Identity")
      end

      def init
        self.value = @builder.wpa_anonymous_identity
      end

      def store
        @builder.wpa_anonymous_identity = value
      end

      def help
        "" # TODO: write it
      end
    end
  end
end
