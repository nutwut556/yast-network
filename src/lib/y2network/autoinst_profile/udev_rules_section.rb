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

require "y2network/autoinst_profile/section_with_attributes"
require "y2network/autoinst_profile/udev_rule_section"

module Y2Network
  module AutoinstProfile
    # This class represents an AutoYaST <net-udev> section under <networking>
    #
    # <net-udev config:type="list">
    #   <rule>
    #     <name>eth0</name>
    #     <rule>ATTR{address}</rule>
    #     <value>00:30:6E:08:EC:80</value>
    #   </rule>
    # </net-udev>
    #
    # @see NetworkingSection
    class UdevRulesSection < SectionWithAttributes
      include Yast::Logger

      def self.attributes
        [
          { name: :udev_rules, xml_name: :"net-udev" }
        ]
      end

      define_attr_accessors

      # @!attribute udev_rules
      #   @return [Array<UdevRuleSection>]

      # Clones network interfaces settings into an AutoYaST interfaces section
      #
      # @param config [Y2Network::Config] whole config as it need both interfaces and connection configs
      # @return [UdevRulesSection]
      def self.new_from_network(config)
        new.tap { |r| r.init_from_network(config) }
      end

      # Constructor
      def initialize(*_args)
        super
        @udev_rules = []
      end

      # Method used by {.new_from_hashes} to populate the attributes when importing a profile
      #
      # @param hash [Array] see {.new_from_hashes}. In this case it is array of udev_rules
      def init_from_hashes(hash)
        @udev_rules = udev_rules_from_hash(hash)
      end

      # Method used by {.new_from_network} to populate the attributes when cloning routing settings
      #
      # @param connection_configs [Y2Network::InterfacesCollection] Network settings
      # @return [Boolean] Result true on success or false otherwise
      def init_from_network(interfaces)
        @udev_rules = udev_rules_section(interfaces)
      end

    private

      # Returns an array of udev rules sections
      #
      # @param hash [Hash] net-udev section hash
      def udev_rules_from_hash(hash)
        hash.map do |h|
          h = h["device"] if h["device"].is_a? ::Hash # hash can be enclosed in different hash
          res = InterfaceSection.new_from_hashes(h)
          log.info "interfaces section #{res.inspect} load from hash #{h.inspect}"
          res
        end
      end

      def udev_rules_section(interfaces)
        interfaces
          .map { |i| Y2Network::AutoinstProfile::UdevRuleSection.new_from_network(i) }
          .compact
      end
    end
  end
end
