class Api::V4::Models
  class << self
    def timestamp
      { type: :string,
        format: 'date-time',
        description: 'Timestamp with millisecond precision.' }
    end

    def uuid
      { type: :string,
        format: :uuid,
        pattern: '[0-9a-fA-F]{8}\-[0-9a-fA-F]{4}\-[0-9a-fA-F]{4}\-[0-9a-fA-F]{4}\-[0-9a-fA-F]{12}' }
    end

    def non_empty_string
      { type: :string,
        minLength: 1,
        description: 'This string should not be empty.' }
    end

    def nullable_timestamp
      timestamp.merge(type: [:string, 'null'])
    end

    def bcrypt_password
      { type: :string,
        pattern: '^\$[0-9a-z]{2}\$[0-9]{2}\$[A-Za-z0-9\.\/]{53}$',
        description: 'Bcrypt password digest' }
    end

    def array_of(type)
      { type: ['null', :array],
        items: { '$ref' => "#/definitions/#{type}" } }
    end

    def blood_sugar
      { type: :object,
        properties: {
          id: { '$ref' => '#/definitions/uuid' },
          blood_sugar_type: { type: :string, enum: BloodSugar.blood_sugar_types.keys },
          blood_sugar_value: { type: :number },
          deleted_at: { '$ref' => '#/definitions/nullable_timestamp' },
          created_at: { '$ref' => '#/definitions/timestamp' },
          updated_at: { '$ref' => '#/definitions/timestamp' },
          recorded_at: { '$ref' => '#/definitions/timestamp' },
          patient_id: { '$ref' => '#/definitions/uuid' },
          facility_id: { '$ref' => '#/definitions/uuid' },
          user_id: { '$ref' => '#/definitions/uuid' } },
        required: %w[id blood_sugar_type blood_sugar_value created_at updated_at patient_id facility_id user_id]
      }
    end

    def definitions
      { timestamp: timestamp,
        uuid: uuid,
        non_empty_string: non_empty_string,
        nullable_timestamp: nullable_timestamp,
        bcrypt_password: bcrypt_password,
        blood_sugar: blood_sugar,
        blood_sugars: array_of('blood_sugar')
      }
    end
  end
end