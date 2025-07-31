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
          'audio/mpeg', 'audio/mp3', 'audio/wav', 'audio/ogg', 'audio/m4a',
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
        
        begin
          # Use the same approach as LensModel - rails_blob_url with only_path: false
          # This works correctly with Backblaze B2 in all environments
          Rails.application.routes.url_helpers.rails_blob_url(media_file, only_path: false)
        rescue => e
          Rails.logger.error "Error generating media URL: #{e.message}"
          Rails.logger.error "Backtrace: #{e.backtrace.first(5).join('\n')}"
          
          # Fallback: try to use the service directly (same as LensModel)
          begin
            media_file.service.url(media_file.key)
          rescue => fallback_error
            Rails.logger.error "Error in fallback: #{fallback_error.message}"
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
    end
end
  