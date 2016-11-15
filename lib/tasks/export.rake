# -*- coding: utf-8 -*-
#rake tasks and supporting models and functions to do research export
namespace :export do

require 'csv'
require 'fileutils'

#create models to access join and translation tables
class InfoRequestBatchPublicBody < ActiveRecord::Base
  self.table_name = "info_request_batches_public_bodies"
  belongs_to :info_request_batch
  belongs_to :public_body
end

class PublicBodyCategoryTranslation < ActiveRecord::Base
  self.table_name = "public_body_category_translations"
  belongs_to :public_body_category
end

class PublicBodyHeadingTranslation < ActiveRecord::Base
  self.table_name = "public_body_heading_translations"
  belongs_to :public_body_heading
end

class HasTagStringTag < ActiveRecord::Base
  self.table_name = "has_tag_string_tags"
end

def case_insensitive_user_censor(text, user)
  # remove all instances of user's name (if there is a user)
  if user == nil
    return text
  else
    return case_insensitive_name_censor(text, user.name)
  end
  name = user.name
end

def case_insensitive_name_censor(text, name)
  # remove all instances of name (case insensitive from text)
  if text == nil
    return nil
  end
	loc = text.downcase.index(name.downcase)
	while loc != nil
		text = text[0...loc] + "<REQUESTER>" + text[loc+name.length..text.length]
		loc = text.downcase.index(name.downcase)
	end
	return text
end

def name_censor_lambda(property)
  #return a lambda to pass to export function that censors x.property
  return lambda {|x| case_insensitive_user_censor(x.send(property),x.info_request.user)}
end

def csv_export(model, query=nil, header=nil, override={})
  # exports a models, can be limited to certain records by passing in query
  # restrict records to export using query
  # restrict columns to export using header
  # use override to pass in lambdas that modify particular column based on other values in the row
  if query == nil
    query = model.all
  end

  if header == nil
    header = model.column_names
  end

  now = Time.now.strftime("%d-%m-%Y")
  filename = "exports/#{model.name}-#{now}.csv"
  FileUtils.mkdir_p('exports')
  puts "exporting to: #{filename}"
  CSV.open(filename, "wb") do |csv|
    csv << header
    query.each do |item|
      line  = []
      for h in header
        if override.key?(h) #do we have an override for this column?
          line.append(override[h][item]) #if so send to lambda
        else
          line.append(item.send(h))
        end
      end
      csv << line
    end
  end
end



desc 'exports all non-personal information to export folder'
task :research_export => :environment do

  csv_export(PublicBodyCategory)
  csv_export(PublicBodyHeading)
  csv_export(PublicBodyCategoryLink)
  csv_export(PublicBodyCategoryTranslation)
  csv_export(PublicBodyHeadingTranslation)
  csv_export(InfoRequestBatch)
  csv_export(InfoRequestBatchPublicBody)
  csv_export(HasTagStringTag, HasTagStringTag.where(model:"PublicBody"))

  #export public body information
  csv_export( PublicBody,
              PublicBody.all,
              ["id",
              "short_name",
              "created_at",
              "updated_at",
              "url_name",
              "home_page",
              "info_requests_count",
              "info_requests_successful_count",
              "info_requests_not_held_count",
              "info_requests_overdue_count",
              "info_requests_visible_classified_count",
              "info_requests_visible_count"])

  #export non-personal user fields
  csv_export( User,
              User.all,
              ["id",
              "name",
              "info_requests_count",
              "track_things_count",
              "request_classifications_count",
              "public_body_change_requests_count",
              "info_request_batches_count",
              ])

  #export InfoRequest Fields
  csv_export(InfoRequest,
             InfoRequest.where(prominence:"normal"),
             ["id",
              "title",
              "user_id",
              "public_body_id",
              "created_at",
              "updated_at",
              "described_state",
              "awaiting_description",
              "url_title",
              "law_used",
              "last_public_response_at",
              "info_request_batch_id"
             ])

  #export incoming messages - only where normal prominence, allow name_censor to some fields
  csv_export(IncomingMessage,
             IncomingMessage.includes(:info_request).where(prominence:"normal").where("info_requests.prominence = ?","normal"),
             ["id",
              "info_request_id",
              "created_at",
              "updated_at",
              "raw_email_id",
              "cached_attachment_text_clipped",
              "cached_main_body_text_folded",
              "cached_main_body_text_unfolded",
              "subject",
              "sent_at",
              "prominence"],
              override = {
                "cached_attachment_text_clipped" => name_censor_lambda('cached_attachment_text_clipped'),
                "cached_main_body_text_folded" => name_censor_lambda('cached_attachment_text_clipped'),
                "cached_main_body_text_unfolded" => name_censor_lambda('cached_attachment_text_clipped'),
              })

  #export incoming messages - only where normal prominence, allow name_censor to some fields
  csv_export(OutgoingMessage,
             OutgoingMessage.includes(:info_request).where(prominence:"normal").where("info_requests.prominence = ?","normal"),
             ["id",
              "info_request_id",
              "created_at",
              "updated_at",
              "body",
              "message_type",
              "subject",
              "last_sent_at",
              "incoming_message_followup_id"
             ],
             override = {
               "body" => name_censor_lambda('body'),
             })

  #export incoming messages - only where normal prominence, allow name_censor to some fields
  csv_export(FoiAttachment,
             FoiAttachment.joins(incoming_message: :info_request).where("info_requests.prominence = ?","normal"),
             ["id",
              "content_type",
              "filename",
              "charset",
              "url_part_number",
              "incoming_message_id",
              "within_rfc822_subject"])

  end

end