#require 'tmail'

class ReceiveMailer < ActionMailer::Base
  #-- For incoming mail

  def receive(email)
    #-- Receive incoming mail.
    #-- See: http://guides.rubyonrails.org/action_mailer_basics.html
  
    #<Mail::Message:2158014300, Multipart: true, Headers: <Return-Path: <ffunch@cr8.com>>, <Received: by draco.cr8.com (Postfix, from userid 10008) id BAA7484D2FDC; Thu, 3 Feb 2011 23:28:39 +0000 (UTC)>, <Received: from mail-qw0-f41.google.com (mail-qw0-f41.google.com [209.85.216.41]) (using TLSv1 with cipher RC4-MD5 (128/128 bits)) (No client certificate requested) by draco.cr8.com (Postfix) with ESMTP id 68DF484CE8FD for <a+b+c@intermix.cr8.com>; Thu, 3 Feb 2011 23:28:37 +0000 (UTC)>, <Received: by qwa26 with SMTP id 26so1323352qwa.28 for <a+b+c@intermix.cr8.com>; Thu, 03 Feb 2011 15:28:36 -0800 (PST)>, <Received: by 10.229.220.144 with SMTP id hy16mr8313346qcb.80.1296775716663; Thu, 03 Feb 2011 15:28:36 -0800 (PST)>, <Received: by 10.229.229.65 with HTTP; Thu, 3 Feb 2011 15:28:36 -0800 (PST)>, <Date: Fri, 04 Feb 2011 00:28:36 +0100>, <From: Flemming Funch <ffunch@cr8.com>>, <To: a+b+c@intermix.cr8.com>, <Message-ID: <AANLkTi=+gHKiLy7-BTtHe-D0zuYpyz2SRKsMwOudcPAf@mail.gmail.com>>, <Subject: test to a+b+c@intermix.cr8.com>, <Mime-Version: 1.0>, <Content-Type: multipart/alternative; boundary=0016362839faf1f380049b691fb9>, <Content-Transfer-Encoding: 7bit>, <X-Original-To: intermix@draco.cr8.com>, <Delivered-To: intermix@draco.cr8.com>, <X-Spam-Checker-Version: SpamAssassin 3.0.6 (2005-12-07) on u15186594.onlinehome-server.com>, <X-Spam-Level: ***>, <X-Spam-Status: No, score=3.3 required=7.0 tests=ADDRESS_IN_SUBJECT,BAYES_50, HTML_00_10,HTML_MESSAGE,HTML_SHORT_LENGTH,RCVD_BY_IP autolearn=no version=3.0.6  
  
    savefile = "/tmp/mail-#{Time.now.strftime("%Y-%m-%d %H:%M")}.txt"
    puts "  saving to: #{savefile}"
    f = File.new(savefile, "wb")
    f.write email.inspect
    f.close          

    logger.info("receive_mailer#receive")
  
    from = email.from.first
    to = email.to.first
    subject = email.subject
    group_id = 0

    puts "  from:#{from} to:#{to} subject:#{subject}"
    logger.info("receive_mailer#receive to:#{to} subject:#{subject}")
  
if false  
puts "headers: #{email.headers.inspect}" if email.headers
puts "header: #{email.header.inspect}" if email.header
puts "email: #{email.methods}"
#myheaders = TMail::Mail.parse(email.header)
#puts "myheaders: #{myheaders.inspect}"
#puts "myheaders['InterMix-ID']: #{myheaders['InterMix-ID']}" if myheaders['InterMix-ID']
puts "InterMix-ID: #{email.header_string('InterMix-ID')}" if email.header_string and email.header_string('InterMix-ID')
return  
end
  
    if to[0,2] == "w+"
      #-- Unique code for the user to post to his wall. w+778685c5b3@go.intermix.org
      code = to[2,100].to_s
      code = to.match('w\+(.*)@')[1]

      puts "  code: #{code}"
      if code == ''
        puts "  w+ code missing"
        logger.info("receive_mailer#receive w+ code missing")
        return
      end
      logger.info("receive_mailer#receive code:#{code}")

      @participant = Participant.where("direct_email_code=?",code).first

    elsif to =~ %r{-list@} or to =~ %r{-admin@} or to =~ %r{-owner@}
      #-- Apparently to a mailing list (group)
    
      if to =~ %r{-admin@}
        type_list_message = 'admin'
      elsif to =~ %r{-owner@}
        type_list_message = 'owner'
      else
        type_list_message = 'list'
      end     
      puts "  type_list_message: #{type_list_message}" 
    
      res = to.match('([^\-]+)-([0-9]+-){0,1}(list|admin|owner)@')
      if res
        shortname = res[1]
        if shortname == ''
          puts "  no group shortname found"
          logger.info("receive_mailer#receive no group shortname identified")
          return
        end
      else
        puts "  no group shortname found"
        logger.info("receive_mailer#receive no group shortname identified")
        return
      end
      reply_to = res[2] if res.length > 2
      shortname = shortname.downcase
      puts "  group shortname:#{shortname}"
      logger.info("receive_mailer#receive group shortname:#{shortname} messagetype:#{type_list_message}")
    
      @group = Group.includes(:participants).find_by_shortname(shortname)
      if not @group
        puts "  group not identified from #{shortname}"
        logger.info("receive_mailer#receive group shortname #{shortname} not recognized")
        return
      end
      group_id = @group.id
      puts "  group: #{group_id}: #{@group.name}"
      
      if not @group.has_mail_list
        puts "  group does not have mailing list turned on"
        logger.info("receive_mailer#receive group does not have mailing list turned on")
        return        
      end        

      @participant = Participant.includes(:groups).find_by_email(from)
    
      @in_group = false
      if @participant
        puts "  participant: #{@participant.name}"
        for xgroup in @participant.groups
          @in_group = true if xgroup.id == @group.id
        end  
        puts "  is group member: #{@in_group}"
      end
          
      if not @participant
        puts "  no participant identified"
        logger.info("receive_mailer#receive no participant identified")
        return
      end
      
      if not @in_group
        puts "  not a member of group"
        logger.info("receive_mailer#receive participant:#{@participant.id} is not a member of group:#{group.id}")
        return
      end

    end

    puts "  ready to move on"

    if not @participant
      puts "  no participant identified"
      logger.info("receive_mailer#receive no participant identified")
      return
    end

    logger.info("receive_mailer#receive participant:#{@participant.id}")

    #-- Get the actual message 
    puts "  getting the actual message" 
    html_content = ''
    short_content = '' 
    if email.multipart? then
      puts '  multipart1'
      p1 = 0
      email.parts.each do |m|
        p1 += 1
        puts "    part #{p1}"
        puts '    main_type:' + m.main_type
        puts '    content_type:' + m.content_type if m.has_content_type?
        puts '    charset:' + m.charset if  m.has_charset?
        puts '    content_disposition: ' + m.content_disposition if m.content_disposition
        puts '    content_transfer_encoding: ' + m.content_transfer_encoding if m.has_content_transfer_encoding?
        puts '    mime_version: ' + m.mime_version if m.has_mime_version?
        puts '    body: ' + m.body.to_s if false
        #puts '    inspect:'+m.inspect
        #puts '  methods:'+m.methods.join(" ")
        if m.content_type[0,22] == "multipart/alternative;" and m.multipart?
          puts '    multipart2'
          p2 = 0
          m.parts.each do |mm|
            p2 += 1
            puts "      subpart #{p2}"
            puts '      main_type:' + mm.main_type
            puts '      content_type:' + mm.content_type if mm.has_content_type?
            puts '      charset:' + mm.charset if  mm.has_charset?
            puts '      content_disposition: ' + mm.content_disposition if mm.content_disposition
            puts '      content_transfer_encoding: ' + mm.content_transfer_encoding if mm.has_content_transfer_encoding?
            puts '      mime_version: ' + mm.mime_version if mm.has_mime_version?
            if mm.content_type[0,9] == 'text/html' or mm.main_type == 'html'
              puts '      getting html content from this'
              html_content = mm.body.to_s
              html_content.force_encoding(mm.charset) if mm.has_charset?
              html_content = html_content.encode(Encoding::UTF_8)
            elsif mm.content_type[0,10] == 'text/plain' or mm.main_type == 'text'
              puts '      getting short content from this'
              short_content = mm.body.to_s
            end   
          end
        else
          if m.content_type[0,9] == 'text/html' or m.main_type == 'html'
            puts '   getting html content from this'
            html_content = m.body.to_s
            html_content.force_encoding(m.charset) if m.has_charset?
            html_content = html_content.encode(Encoding::UTF_8)
          elsif m.content_type[0,10] == 'text/plain' or m.main_type == 'text'
            puts '  getting short content from this'
            short_content = m.body.to_s
          end   
        end 
      end
    else
       puts '    not multipart. Getting html content from email.body'
       html_content = email.body.to_s
       html_content.force_encoding(email.charset) if email.has_charset?
       html_content = html_content.encode(Encoding::UTF_8)
    end 
    if html_content.to_s == ""
      puts "  didn't get html_content. getting dirty version from body"
      html_content = email.body.to_s
      html_content.force_encoding(email.charset) if email.has_charset?
      html_content = html_content.encode(Encoding::UTF_8)
    end 

    puts "  html_content before cleaning up: #{html_content}"
    
    #-- Try to remove old quotes, footers, personal login info, etc.
    html_content.gsub!(%r{[0-9]+/[0-9]+/[0-9]+ InterMix .*$}m,"")    
    html_content.gsub!(%r{The following message was posted on InterMix.*$}m,"")    
    html_content.gsub!(%r{<div class="gmail_quote">.*$}m,"")
    html_content.gsub!(%r{<div class="gmail_extra">.*$}m,"")   
    html_content.gsub!(%r{-----Original Message-----.*$}m,"")
    html_content.gsub!(/<p id="following">.*$/m,"")
    html_content.gsub!(/<p id="footer">.*$/m,"")
    html_content.gsub!(/auth_token=[^"]+/,"")
    
    puts "  html_content after cleaning up: #{html_content}"
    puts "  html_content encoding: #{html_content.encoding}"
    f = File.new("/tmp/html_content.txt", "wb")
    f.write html_content
    f.close    
    #html_content = html_content.encode("UTF-8")
    #puts "  html_content now: #{html_content.encoding}"
    
    short_content.gsub!(%r{[0-9]+/[0-9]+/[0-9]+ InterMix .*$}m,"")
    short_content = ( html_content.gsub(/(<[^>]*>)|\n|\t/s) {" "} )[0,140] if short_content.to_s == ""
    short_content = short_content[0,140] if short_content.length > 140
    puts "  got it"                
           
    #-- Now, let's see where we'll send it, to list or auto-answer or message to somebody...    
    
    
    if @group and  type_list_message == 'admin'
      #-- Respond to admin requests or send back admin instructions.
      puts "  responding to admin request"
      xcommand = short_content.strip.split(/[\r\n]+/)[0]
      if xcommand != ''
        msubject = "[#{@group.shortname}] Mailing list administration"
        mmessage = "<p>What you sent: \"#{xcommand}\"</p>"
        if xcommand =~ %r{^help}
          mmessage += "<p>You can find instructions below</p>"
        elsif xcommand =~ %r{^subscribe}
          mmessage += "<p>Thank you for your subscription request</p>"
        elsif xcommand =~ %r{^unsubscribe}
          mmessage += "<p>Thank you for your unsubscription request</p>"
        else
          mmessage += "<p>We didn't recognize that as a command</p>"  
        end  
      else
        msubject = "[#{@group.shortname}] Mailing list instructions"
        mmessage = ""
      end    
      puts "  preparing and sending system message"
      begin
        mmessage += render_to_string :action=>"receive_mailer/instructions"
      rescue
        puts "  couldn't render template"
      end
      begin
        email = SystemMailer.generic("#{@group.shortname}-admin@#{ROOTDOMAIN}", from, msubject, mmessage)
        email.deliver
        logger.info("receive_mailer#receive sent back admin instructions")
        puts "  finished responding"
      rescue
        puts "  couldn't send message"
      end
      return
    elsif @group and  type_list_message == 'owner'
      #-- Don't post. Forward the message to the list owner
      puts "  forwardign to list owner"
      if @group.owner.to_i > 0
        owner = Participant.find_by_id(@group.owner)
        if owner
          puts "  owner: #{owner.name} <#{owner.email}>"
          @message = Message.new
          @message.from_participant_id = @participant.id          
          @message.to_participant_id = owner.id
          @message.subject = subject
          @message.message = html_content
          @message.sendmethod = 'web'
          @message.sent_at = Time.now
          if @message.save
            if owner.private_email == 'instant'
              @message.sendmethod = 'email'
              @message.emailit
            end  
            logger.info("receive_mailer#receive Message forwarded to list owner")  
          else
            puts "  but there was a problem saving the message"
            logger.info("receive_mailer#receive Couldn't save message for list owner")  
          end  
        else
          puts "  except for that we can't find the list owner"
          logger.info("receive_mailer#receive Can't find list owner")  
        end  
      else
        puts "  except for that there is no list owner"  
      end             
      return     
    end
    
# NB: At this point we aren't posting items through email
return     
                      
    puts "  now creating an item"
    @item = Item.new
    @item.item_type = 'message'
    @item.media_type = 'text'
    @item.posted_by = @participant.id
    @item.posted_via = 'email'
    @item.subject = subject
    @item.group_id = group_id if group_id > 0
    @item.first_in_thread_group_id = group_id if group_id > 0
    @item.html_content = html_content
    @item.short_content = short_content
    @item.subgroup_list.add('none')
    if reply_to
      @item.reply_to = reply_to 
      @item.is_first_in_thread = false
      @olditem = Item.find_by_id(@item.reply_to)
      if @olditem
        @item.first_in_thread = @olditem.first_in_thread
        @item.first_in_thread_group_id = @olditem.first_in_thread_group_id
        @item.subgroup_list = @olditem.subgroup_list if @olditem.subgroup_list.to_s != ''
        @item.dialog_id = @olditem.dialog_id if @olditem.dialog_id.to_i > 0
        if @item.dialog_id
          @dialog = Dialog.find_by_id(@item.dialog_id)
          @item.period_id = @dialog.current_period if @dialog
          #-- Check if replies are allowed for that dialog/period
          if not @dialog.settings_with_period['allow_replies']
            #-- They're not
            puts "  replies not allowed"
            logger.info("receive_mailer#receive replies not allowed for dialog/period #{@item.dialog_id}/#{@item.period_id.to_i}")
            return
          end
        end
      end
    else
      @item.is_first_in_thread = true
    end
    
    @item.save!
    puts "  item #{@item.id} created"
    logger.info("receive_mailer#receive item #{@item.id} created")
    if @item.is_first_in_thread
      @item.first_in_thread = @item.id    
      @item.save   
    elsif not @item.first_in_thread and @item.reply_to
      @item.first_in_thread = @item.reply_to    
      @item.save   
    end  
    puts "  html_content after saving: #{@item.html_content}"
    
      
  end

end