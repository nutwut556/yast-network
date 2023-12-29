#
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
require "y2packager/package"
require "y2packager/resolvable"
require "y2network/backend"
require "network/network_autoconfiguration"

module Y2Network
  # Class that stores the proposal settings for network during installation.
  class ProposalSettings
    include Yast::Logger
    include Yast::I18n

    # @return [Symbol] network service to be used after the installation (:wicked, :network_manager
    #   or:none)
    attr_accessor :selected_backend
    # @return [Boolean]
    attr_accessor :virt_bridge_proposal
    # @return [Boolean]
    attr_accessor :ipv4_forward
    # @return [Boolean]
    attr_accessor :ipv6_forward
    # @return [Boolean]
    attr_accessor :defaults_applied

    DEFAULTS = [:ipv4_forward, :ipv6_forward].freeze

    # Constructor
    def initialize
      Yast.import "Arch"
      Yast.import "ProductFeatures"

      Yast.import "Package"
      Yast.import "PackagesProposal"
      Yast.import "Lan"

      @selected_backend = autoinst_backend
      @virt_bridge_proposal = !autoinst_disabled_proposal?
      @defaults_applied = false
    end

    # Modifies the proposal according to the given settings
    #
    # @param settings [Hash] network default settings to be loaded
    def modify_defaults(settings = network_section)
      load_features(settings)
      @defaults_applied = false
    end

    # Modifies the current network configuration according to the proposal. It does not touch the
    # network configuration if the proposal settings were already applied
    def apply_defaults
      return if defaults_applied
      return @defaults_applied = true if DEFAULTS.all? { |o| public_send(o).nil? }

      Yast::Lan.read_config(report: false) unless yast_config
      yast_config.routing.forward_ipv4 = ipv4_forward unless ipv4_forward.nil?
      yast_config.routing.forward_ipv6 = ipv6_forward unless ipv6_forward.nil?
      @defaults_applied = true
    end

    def current_backend
      selected_backend || default_backend
    end

    def default_backend
      default = use_network_manager? ? :network_manager : :wicked
      log.info "The default backend is: #{default}"
      default
    end

    def propose_bridge?
      virtual_proposal_required? && virt_bridge_proposal
    end

    def propose_bridge!(option)
      log.info("Bridge proposal set to: #{option.inspect}")
      @virt_bridge_proposal = option
    end

    # Adds the NetworkManager package to the Yast::PackagesProposal and sets
    # NetworkManager as the backend to be used
    def enable_network_manager!
      log.info "Enabling NetworkManager"
      self.selected_backend = :network_manager
      refresh_packages

      selected_backend
    end

    # Add the wicked package to the Yast::PackagesProposal and sets wicked
    # as the backend to be used
    def enable_wicked!
      log.info "Enabling Wicked"
      self.selected_backend = :wicked
      refresh_packages

      selected_backend
    end

    def disable_network!
      log.info "Disabling all network services"
      self.selected_backend = :none
    end

    def refresh_packages
      case current_backend
      when :network_manager
        Yast::PackagesProposal.AddResolvables("network", :package, ["NetworkManager"])
        Yast::PackagesProposal.RemoveResolvables("network", :package, ["wicked"])
      when :wicked
        Yast::PackagesProposal.AddResolvables("network", :package, ["wicked"])
        Yast::PackagesProposal.RemoveResolvables("network", :package, ["NetworkManager"])
      when :none
        Yast::PackagesProposal.RemoveResolvables("network", :package, ["NetworkManager"])
        Yast::PackagesProposal.RemoveResolvables("network", :package, ["wicked"])
      end
    end

    # Convenience method to obtain whether the NetworkManager package is
    # available or not.
    #
    # @return [Boolean] false if no package available, true otherwise
    def network_manager_available?
      p = Y2Packager::Package.find("NetworkManager").first
      if p.nil?
        log.info("The NetworkManager package is not available")
        return false
      end
      log.info("The NetworkManager package status: #{p.status}")
      true
    end

    # Decides if a proposal for virtualization host machine is required.
    def virtual_proposal_required?
      return false if Yast::Arch.s390

      return true if package_selected?("xen") && Yast::Arch.is_xen0
      return true if package_selected?("kvm")
      return true if package_selected?("qemu")

      false
    end

    # Propose the network service to be use at the end of the installation
    # depending on the backend selected during the proposal and the packages
    # installed
    #
    # @return [Symbol] :network_manager, :wicked or :none
    def network_service
      case current_backend
      when :network_manager
        return :network_manager if network_manager_installed?

        log.info("NetworkManager is the selected service but it is not installed")
        log.info("- using wicked")

        return :wicked
      when :wicked
        return :wicked if wicked_installed?

        return :none unless network_manager_installed?

        log.info("Wicked is the selected service but it is not installed - using Network Manager")

        return :network_manager
      end

      current_backend
    end

    class << self
      # Singleton instance
      def instance
        @instance ||= create_instance
      end

      # Enforce a new clean instance
      def create_instance
        @instance = new
      end

      # Make sure only .instance and .create_instance can be used to
      # create objects
      private :new, :allocate
    end

  private

    # Convenience method to load some features from a installation control file section
    #
    # @param source [Hash] network section to be loaded
    def load_features(source = network_section)
      return unless source.is_a?(Hash)

      source.each_key { |k| load_feature(k, k, source: source) }
    end

    # Reads a feature from a given hash and assign it to the corresponding object attribute
    #
    # @param feature [String, Symbol] feature name to be read
    # @param to [String, Symbol] attribute name where to store the feature value
    # @param source [Hash] from where to read the feature
    def load_feature(feature, to, source: network_section)
      return unless respond_to?("#{to}=")

      value = source[feature.to_s]
      public_send("#{to}=", value)
    end

    # Convenience method to read the control file network section
    def network_section
      Yast::ProductFeatures.GetSection("network")
    end

    def yast_config
      Yast::Lan.yast_config
    end

    def autoinst_backend
      Yast::Lan.autoinst.selected_backend
    end

    # Convenience method to check whether the bridge configuration proposal for
    # configuration was disabled in the AutoYaST profile.
    def autoinst_disabled_proposal?
      Yast::Lan.autoinst.virt_bridge_proposal == false
    end

    # Convenience method to check whether a specific package is selected to be
    # installed
    def package_selected?(name)
      Y2Packager::Resolvable.any?(kind: :package, name: name, status: :selected)
    end

    # Convenienve method that verify if Network Manager should be used or not
    # according to the control file defaults and package availability.
    #
    # @return [Boolean] true if should be used; false otherwise
    def use_network_manager?
      return false unless network_manager_available?

      network_manager_default?
    end

    # Convenience method to determine if the NM package is installed or not
    #
    # @return [Boolean] true if NetworkManager is installed; false otherwise
    def network_manager_installed?
      Yast::Package.Installed("NetworkManager")
    end

    # Convenience method to determine if the NM package is installed or not
    #
    # @return [Boolean] true if wickedis installed; false otherwise
    def wicked_installed?
      Yast::Package.Installed("wicked")
    end

    # Determine whether NetworkManager should be selected by default according
    # to the product control file
    #
    # @return [Boolean] true if NM should be enabled; false otherwise
    def network_manager_default?
      case Yast::ProductFeatures.GetStringFeature("network", "network_manager")
      when ""
        # compatibility: use the boolean feature
        # (defaults to false)
        Yast::ProductFeatures.GetBooleanFeature("network", "network_manager_is_default")
      when "always"
        true
      when "laptop"
        laptop = Yast::Arch.is_laptop
        log.info("Is a laptop: #{laptop}")
        laptop
      end
    end
  end
end
