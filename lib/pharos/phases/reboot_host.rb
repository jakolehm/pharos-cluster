# frozen_string_literal: true

module Pharos
  module Phases
    class RebootHost < Pharos::Phase
      title "Reboot hosts"

      EXPECTED_ERRORS = [
        Net::SSH::Disconnect,
        Net::SSH::ConnectionTimeout,
        Net::SSH::Timeout,
        Errno::EHOSTDOWN,
        Pharos::ExecError
      ].freeze

      def call
        return host.transport.exec!("sudo shutdown -r now") if host.local?

        reboot
        reconnect
        uncordon
      end

      def reboot
        logger.debug "Sending the reboot command .."
        transport.exec!('sudo nohup bash -c "sleep 5; shutdown -r now" &> /dev/null &')
        transport.disconnect
        logger.debug { "Allowing the host some time to start the shutdown process .." }
        sleep 20
      end

      def reconnect
        logger.info "Reconnecting and waiting for kubelet to start .."
        Pharos::Retry.perform(1200, exceptions: EXPECTED_ERRORS, logger: logger) do
          transport.connect unless transport.connected?
          transport.exec!('systemctl is-active kubelet')
        end
        logger.debug "Connected"
      end

      def uncordon
        logger.info "Uncordoning .."
        Pharos::Retry.perform(logger: logger, exceptions: EXPECTED_ERRORS) do
          master_host.transport.exec!("kubectl uncordon #{host.hostname} | grep -q 'already uncordoned'")
        end
      end
    end
  end
end