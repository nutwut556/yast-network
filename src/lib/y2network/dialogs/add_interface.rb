require "cwm/dialog"
require "y2network/widgets/interface_type"

Yast.import "Label"
Yast.import "LanItems"
Yast.import "NetworkInterfaces"

module Y2Network
  module Dialogs
    # Dialog which starts new device creation
    class AddInterface < CWM::Dialog
      def initialize(builder)
        @type_widget = Widgets::InterfaceType.new
        @builder = builder
      end

      def contents
        HBox(
          @type_widget
        )
      end

      def run
        ret = super
        log.info "AddInterface result #{ret}"
        ret = :back if ret == :abort

        # TODO: replace with builder initialization
        if ret == :back
          Yast::LanItems.Rollback
        else
          @builder.type = @type_widget.result
          proposed_name = Yast::LanItems.new_type_devices(@type_widget.result, 1).first
          @builder.name = proposed_name
          Yast::NetworkInterfaces.Name = proposed_name
          Yast::LanItems.Items[Yast::LanItems.current]["ifcfg"] = proposed_name
          Yast::LanItems.Items[Yast::LanItems.current]["udev"] = {}
        end

        ret
      end

      def back_button
        ""
      end

      def abort_button
        Yast::Label.CancelButton
      end

      # always open new dialog
      def should_open_dialog?
        true
      end
    end
  end
end
