module Seek
  module WorkflowExtractors
    class Galaxy < Base
      def self.file_extensions
        ['ga']
      end

      def metadata
        metadata = super
        galaxy_string = @io.read
        galaxy = JSON.parse(galaxy_string)
        if galaxy.has_key?('name')
          metadata[:title] = galaxy['name']
        else
          metadata[:warnings] << 'Unable to determine title of workflow'
        end

        metadata[:license] = galaxy['license'] if galaxy['license']

        if galaxy['creator']
          creators = Array(galaxy['creator']).select { |c| c['class'] == 'Person' }.map { |c| c['name'] }
          metadata[:other_creators] = creators.join(', ') if creators.any?
        end

        metadata[:internals] = {}
        metadata[:internals][:inputs] = []
        metadata[:internals][:outputs] = []
        metadata[:internals][:steps] = []
        galaxy['steps'].each do |num, step|
          (step['inputs'] || []).each do |input|
            metadata[:internals][:inputs] << { id: input['name'], name: input['label'] || input['name'], description: input['description'] }
          end

          (step['outputs'] || []).each do |output|
            metadata[:internals][:outputs] << { id: output['name'], name: output['label'] || output['name'], type: output['type'] }
          end

          metadata[:internals][:steps] << { id: step['id'], name: step['label'] || step['name'], description: (step['annotation'] || '') + "\n " + (step['tool_id'] || '') }
        end

        metadata[:tags] = galaxy['tags']

        metadata
      end
    end
  end
end
