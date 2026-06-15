module ClinicManagement
    class LeadMessage < ApplicationRecord
      enum message_type: { confirmação: 0, 
                           remarcação: 1, 
                           lembrete: 2, 
                           recuperação_mesmo_dia: 4,
                           recuperação_dois_dias: 5,
                           recuperação_sete_dias: 6,
                           recuperação_quinze_dias: 7,
                           recuperação_dois_meses: 8,
                           outro: 3 }
      belongs_to :service_type, optional: true
      # ESSENTIAL: Optional - nil = global (applies to all locations).
      # When set, message is specific to that ServiceLocation (e.g. Ótica Light).
      belongs_to :service_location, optional: true, class_name: "ClinicManagement::ServiceLocation"
      # ESSENTIAL: Explicit Meta template for automation when account channel is meta.
      belongs_to :meta_template, optional: true, class_name: "MetaTemplate"

      DELIVERY_CHANNELS = %w[evolution meta].freeze

      validates :delivery_channel, inclusion: { in: DELIVERY_CHANNELS }, allow_nil: true
      validate :meta_template_must_be_valid_for_slot, if: -> { meta_template_id.present? }
      
      # Active Storage attachment for media files (images, audio, video, pdf)
      has_one_attached :media_file
      
      # Validation for media file types using Active Storage
      validate :acceptable_media_file, if: -> { media_file.attached? }
      
      # Callback to set media_type automatically
      before_save :set_media_type_from_file
      
      private
      
      def acceptable_media_file
        return unless media_file.attached?
        
        acceptable_types = [
          'image/jpeg', 'image/jpg', 'image/png', 'image/gif', 'image/webp',
          'audio/mpeg', 'audio/mp3', 'audio/mp4', 'audio/wav', 'audio/ogg', 'audio/opus', 'audio/m4a',
          'video/mp4', 'video/avi', 'video/mov', 'video/wmv', 'video/webm',
          'application/pdf'
        ]
        
        unless acceptable_types.include?(media_file.content_type)
          errors.add(:media_file, 'deve ser uma imagem, áudio, vídeo ou PDF')
        end
        
        # Check file size (max 50MB)
        if media_file.byte_size > 50.megabytes
          errors.add(:media_file, 'deve ter no máximo 50MB')
        end
      end
      
      def set_media_type_from_file
        if media_file.attached? && media_file.content_type.present?
          self.media_type = whatsapp_media_type
        end
      end
      
      public
      
      # Check if message has media attachment
      def has_media?
        media_file.attached?
      end
      
      # Get media URL for WhatsApp sending
      def media_url
        return nil unless has_media?
        
        # Different approach based on storage service
        if Rails.env.development?
          # For localhost development with local storage, use HTTP with explicit host
          Rails.application.routes.url_helpers.rails_blob_url(media_file, host: 'localhost:3000', protocol: 'http')
        else
          # For staging/production with Backblaze B2, use service directly to avoid host issues
          begin
            media_file.service.url(media_file.key)
          rescue => e
            Rails.logger.error "Error generating media URL: #{e.message}"
            Rails.logger.error "Backtrace: #{e.backtrace.first(5).join('\n')}"
            nil
          end
        end
      end
      
      # Determine media type for WhatsApp API
      def whatsapp_media_type
        return nil unless has_media?
        
        content_type = media_file.content_type
        case content_type
        when /^image\//
          'image'
        when /^audio\//
          'audio'
        when /^video\//
          'video'
        when 'application/pdf'
          'document'
        else
          'document'
        end
      end

      # ESSENTIAL: Hybrid channel — account default + slot override + media → Evolution.
      #
      # @param account [Account]
      # @return [Symbol] :evolution | :meta
      def effective_delivery_channel(account)
        ClinicAutomationChannelResolver.resolve(account: account, lead_message: self)
      end

      private

      def meta_template_must_be_valid_for_slot
        return if meta_template.blank?

        unless meta_template.approved?
          errors.add(:meta_template, "deve estar aprovado na Meta")
        end
      end
    end
end
  