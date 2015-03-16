class ExportJob < ActiveJob::Base
  queue_as :export

  TYPES = %w(csv xml)
  CLASSES = %w(people groups)

  def perform(site, table, type, person_id)
    return unless CLASSES.include?(table)
    return unless TYPES.include?(type)
    klass = table.classify.constantize
    ActiveRecord::Base.connection_pool.with_connection do
      Site.with_current(site) do
        data = klass.send("to_#{type}")
        file = FakeFile.new(data, "#{table}.#{type}")
        GeneratedFile.create!(
          job_id:    job_id,
          person_id: person_id,
          file:      file
        )
      end
    end
  end
end
