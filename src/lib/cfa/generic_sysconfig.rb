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

require "cfa/base_model"
require "cfa/augeas_parser"
require "cfa/matcher"

require "yast"

module CFA
  class GenericSysconfig < BaseModel
    include Yast::Logger

    def initialize(path, file_handler: nil)
      super(AugeasParser.new("Sysconfig.lns"), path, file_handler: file_handler)
    end

    # attributes in file
    # @return [Hash<String, String>] key with its value
    def attributes
      attrs = data.select(CFA::Matcher.new { |k, _v| k != "#comment[]" })
      attrs.map { |v| [v[:key], v[:value]] }.to_h
    end

    # do merge of sysconfigs value in a sense that values not in new file is kept in
    # the original one and also all comments are kept.
    # @param original_path [String] path to the original file. SCR root is NOT applied
    # @param modified_path [String] path to the modified file. SCR root is NOT applied
    def self.merge_files(original_path, modified_path)
      # use ::File handle to ensure that SCR is not taken in account
      modified_model = new(modified_path, file_handler: ::File)
      target_model = new(original_path, file_handler: ::File)

      modified_model.load
      # if old part into which we merge does not exist, then just copy new content
      begin
        target_model.load
      rescue IOError, SystemCallError => e
        log.error "Failed to load #{original_path} with #{e.inspect}. Copying just new content."
        ::FileUtils.cp modified_path, original_path
        return
      end

      modified_model.attributes.each_pair do |key, value|
        target_model.generic_set(key, value)
      end

      target_model.save
    end
  end
end
