require 'shellwords'
require 'travis/build/appliances/base'

module Travis
  module Build
    module Appliances
      class Services < Base

        include Template

        SERVICES = {
          'hbase'        => 'hbase-master', # for HBase status, see travis-ci/travis-cookbooks#40. MK.
          'memcache'     => 'memcached',
          'neo4j-server' => 'neo4j',
          'rabbitmq'     => 'rabbitmq-server',
          'redis'        => 'redis-server'
        }
        TEMPLATES_PATH = File.expand_path('../../templates', __FILE__)

        def apply
          sh.if '"$TRAVIS_OS_NAME" != "linux"' do
            sh.echo 'Services are not supported on "$TRAVIS_OS_NAME"', ansi: :red
          end
          sh.else do
            sh.fold 'services' do
              services.each do |name|
                service_apply_method = "apply_#{name}"
                if respond_to?(service_apply_method)
                  send(service_apply_method)
                  next
                end
                sh.if '"$TRAVIS_INIT" == upstart' do
                  sh.cmd "sudo service #{name.shellescape} start", assert: false, echo: true, timing: true
                end
                sh.elif '"$TRAVIS_INIT" == systemd' do
                  sh.cmd "sudo systemctl start #{name.shellescape}", assert: false, echo: true, timing: true
                end
              end
              sh.raw 'sleep 3'
            end
          end
        end

        def apply?
          services.any?
        end

        def apply_mongodb
          sh.if '"$TRAVIS_DIST" == precise' do
            sh.cmd 'sudo service mongodb start', echo: true, timing: true
          end
          sh.elif '"$TRAVIS_INIT" == upstart' do
            sh.cmd 'sudo service mongod start', echo: true, timing: true
          end
          sh.elif '"$TRAVIS_INIT" == systemd' do
            sh.cmd 'sudo systemctl start mongod', echo: true, timing: true
          end
        end

        def apply_mysql
          sh.raw <<~BASH
            travis_mysql_ping() {
              local i timeout=10
              until (( i++ >= $timeout )) || mysql <<<'select 1;' >&/dev/null; do sleep 1; done
              if (( i > $timeout )); then
                echo -e "${ANSI_RED}MySQL did not start within ${timeout} seconds${ANSI_RESET}"
              fi
              unset -f travis_mysql_ping
            }
          BASH
          sh.if '"$TRAVIS_INIT" == upstart' do
            sh.cmd 'sudo service mysql start', assert: false, echo: true, timing: true
          end
          sh.elif '"$TRAVIS_INIT" == systemd' do
            sh.cmd 'sudo systemctl start mysql', assert: false, echo: true, timing: true
          end
          sh.cmd 'travis_mysql_ping'
        end

        def apply_postgresql
          return if data[:config]&.[](:addons)&.[](:postgresql)
          sh.raw(template('postgresql.sh', version: nil), echo: false, timing: false)
          sh.cmd 'travis_setup_postgresql', echo: true, timing: true
        end

        private

          def services
            @services ||= Array(config[:services]).map do |name|
              normalize(name)
            end
          end

          def normalize(name)
            name = name.to_s.downcase
            SERVICES[name] ? SERVICES[name] : name
          end
      end
    end
  end
end
