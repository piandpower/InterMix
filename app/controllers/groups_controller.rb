require 'will_paginate/array'

class GroupsController < ApplicationController
 
	layout "front"
  append_before_action :authenticate_user_from_token!
  append_before_action :authenticate_participant!
  append_before_action :check_group_and_dialog, :check_required, :check_status
  append_before_action :redirect_subdom, :except => :index

  def index
    #-- Show an overview of groups this person has access to
    @section = 'groups'
    @gsection = 'index'
    @groupsin = GroupParticipant.where("participant_id=#{current_participant.id}").select("distinct(group_id),moderator").includes(:group)
    @groupsina = @groupsin.collect{|g| g.group.id if g.group }
    @ismoderator = false
    session.delete(:list_sortby) if session.include?(:list_sortby) 
    session.delete(:slider_period_id) if session.include?(:slider_period_id)
    for group in @groupsin
      @ismoderator = true if group.moderator
    end  
    @groupsopen = Group.where("(openness='open' or openness='open_to_apply')").order("id desc")
    @groupspublic = Group.where("visibility='public'").order("id desc")
    update_last_url
  end  
  
  def view
    #-- Presentation for a group one might want to join
    @section = 'groups'
    @gsection = 'info'
    @group = Group.includes(:owner_participant).find(params[:id])
    get_group_info
    update_last_url
    update_prefix
  end  
  
  def admin
    #-- Overview page for administrators and moderators
    @section = 'groups'
    @gsection = 'admin'
    @group = Group.find(params[:id])
    get_group_info
    update_last_url
    update_prefix
  end
  
  def moderate
    #-- Main screen for a group moderator
    @section = 'groups'
    @gsection = 'moderate'
    @group = Group.find(params[:id])
    get_group_info
    update_last_url
    update_prefix
  end  
  
  def new
    #-- Creating a new group
    @section = 'groups'
    @group = Group.new
    @group.owner = current_participant.id
    @group.participants << current_participant
    @metamaps = Metamap.where(nil)
    @has_metamaps = {}
    render :action=>'edit'
  end  
  
  def edit
    #-- Editing group information, only for administrators
    @section = 'groups'
    #@group = Group.includes(:group_participants=>:participant).find(params[:id])
    @group = Group.includes(:owner_participant).find(params[:id])
    get_group_info
    @metamaps = Metamap.where(nil)
    @has_metamaps = {}
    for metamap in @group.metamaps
      @has_metamaps[metamap.id] = true
    end
    render :action=>'edit'
    update_prefix
  end  
  
  def update
    @group = Group.find(params[:id])
    @metamaps = Metamap.where(nil)
    #logger.info("groups#update metamap parameter: #{params[:metamap]}")
    respond_to do |format|
      if gvalidate and @group.update_attributes(group_params)
        @group.shortdesc = view_context.strip_tags(@group.shortdesc)[0..123]
        @group.save
        for metamap in Metamap.where(nil)
          group_metamap = GroupMetamap.where(:group_id=>@group.id,:metamap_id=>metamap.id).first
          #logger.info("groups#update metamap:#{metamap.id} param:#{params[:metamap][metamap.id.to_s]} group_metamap:#{group_metamap}")
          if params[:metamap] and params[:metamap][metamap.id.to_s] and not group_metamap
            #logger.info("groups#update metamap:#{metamap.id} being set")
            group_metamap = GroupMetamap.new(:group_id=>@group.id,:metamap_id=>metamap.id)
            group_metamap.save!
          elsif (not params[:metamap] or not params[:metamap][metamap.id.to_s]) and group_metamap
            #logger.info("groups#update metamap:#{metamap.id} being deleted")
            group_metamap.destroy
          else
            #logger.info("groups#update metamap:#{metamap.id} no change")
          end  
        end
        format.html { redirect_to :action=>:view, :notice => 'Group was successfully updated.' }
        format.xml  { head :ok }
      else
        @has_metamaps = {}
        for metamap in @group.metamaps
          @has_metamaps[metamap.id] = true
        end
        get_group_info
        format.html { render :action => "edit" }
        format.xml  { render :xml => @group.errors, :status => :unprocessable_entity }
      end
    end
  end  
  
  def gvalidate
    flash[:alert] = ''
    if params[:group][:name].to_s == ''
      flash[:alert] += "The group needs a name<br/>"
    elsif params[:group][:shortname].to_s == ''
      flash[:alert] += "The group needs a short name, used for example in e-mail [subject] lines<br/>"
    else
      #-- Check if the shortname is unique
      xshortname = params[:group][:shortname]
      xgroup = Group.where("shortname='#{xshortname}' and id!=#{@group.id.to_i}").first
      if xgroup
        flash[:alert] += "There is already another group with the prefix \"#{xshortname}\"<br/>"
      else  
        xdialog = Dialog.where("shortname='#{xshortname}'").first
        if xdialog
          flash[:alert] += "There is already a discussion with the prefix \"#{xshortname}\"<br/>"
        end  
      end  
    end
    if params[:group][:owner].to_i == 0
      flash[:alert] += "Who is the owner of the group? Most likely you.<br/>"
    end  
    if params[:group][:openness].to_s == ''
      flash[:alert] += "Please choose a membership setting<br/>"
    end
    if params[:group][:visibility].to_s == ''
      flash[:alert] += "Please set the visibility<br/>"
    end
    logger.info("groups_controller#gvalidate failed: #{flash[:alert]}") if flash[:alert] != ''
    flash[:alert] == ''
  end  
  
  def create
    @group = Group.new(group_params)
    @group.participants << current_participant
    @metamaps = Metamap.where(nil)
    respond_to do |format|
      if gvalidate and @group.save
        logger.info("groups_controller#create New group created: #{@group.id}")
        @group_participant = GroupParticipant.where("group_id = ? and participant_id = ?",@group.id,current_participant.id).first
        @group_participant.status = 'active'
        @group_participant.moderator = true
        @group_participant.active = true
        @group_participant.save
        for metamap in Metamap.where(nil)
          group_metamap = GroupMetamap.where(:group_id=>@group.id,:metamap_id=>metamap.id).first
          if params[:metamap] and params[:metamap][metamap.id.to_s] and not group_metamap
            group_metamap = GroupMetamap.new(:group_id=>@group.id,:metamap_id=>metamap.id)
            group_metamap.save!
          elsif (not params[:metamap] or not params[:metamap][metamap.id.to_s]) and group_metamap
            group_metamap.destroy
          end  
        end
        flash[:notice] = 'Group was successfully created.'
        format.html { redirect_to :action=>:view, :id=>@group.id }
      else
        logger.info("groups_controller#create Failed creating new group")
        @has_metamaps = {}
        #get_group_info
        format.html { render :action=>:edit }
      end
    end
    update_prefix
  end  
  
  def dialogs
    #-- List of discussions that apply to this group
    @section = 'groups'
    @gsection = 'dialogs'
    @group_id = params[:id]
    @group = Group.joins(:group_participants=>:participant).includes(:dialogs).where("group_participants.group_id=#{@group_id}").find(params[:id])
    get_group_info
    update_last_url
    update_prefix  
    @admin4 = DialogAdmin.where("participant_id=?",current_participant.id).collect{|r| r.dialog_id}  
  end  
  
  def members
    #-- List of members, for other members
    @section = 'groups'
    @group_id = params[:id]
    @group = Group.joins(:group_participants=>:participant).where("group_participants.group_id=#{@group_id}").find(params[:id])

    get_group_info

    if not @is_member
      redirect_to "/groups/#{@group_id}"
      return
    end

    @members = @group.active_members
    @title = "Group members" 

    update_last_url
    update_prefix
  end  
  
  def members_admin
    #-- List of members, for admins
    @section = 'groups'
    @group_id = params[:id]
    @group = Group.joins(:group_participants=>:participant).where("group_participants.group_id=#{@group_id}").find(params[:id])

    get_group_info

    if not ( (@is_member and @is_moderator) or session[:is_hub_admin] or session[:is_sysadmin] )
      redirect_to "/groups/#{@group_id}"
      return
    end

    if params.include? :active
      if params[:active].to_i == 1
        @active = 1
        @members = @group.active_members
        @title = "Active members"
      else
        @active = 0
        @members = @group.non_active_members
        @title = "Non-active members"
      end
    else
      @active = -1
      #@members = @group.participants     # problem with having several group_participants records
      @members = @group.members_with_group_participants
      @title = "All members (active and in-active)"
    end    

    update_last_url
    update_prefix
  end 
  
  def subgroups
    #-- Show the subgroups that exist and number of members
    @section = 'groups'
    @gsection = 'subgroups'
    @group_id = params[:id]
    @group = Group.includes(:group_participants=>:participant).find(@group_id)
    get_group_info    
  end  
  
  def subgroup_members
    #-- List members/followers of a particular subgroup
    #-- Show the subgroups that exist and number of members
    @section = 'groups'
    @gsection = 'subgroups'
    @group_id = params[:id]
    @group = Group.includes(:group_participants=>:participant).find(@group_id)
    @subgroup_id = params[:subgroup_id]
    @subgroup = GroupSubtag.find_by_id(@subgroup_id)
    @members = GroupSubtagParticipant.where(:group_id=>@group.id).where(:group_subtag_id=>@subgroup.id)
    get_group_info    
  end  
  
  def subgroup_join
    #-- Current user joining a subgroup
    @section = 'groups'
    @gsection = 'subgroups'
    @group_id = params[:id]
    @subgroup_id = params[:subgroup_id]
    @subgroup = GroupSubtag.find(@subgroup_id)
    member = GroupSubtagParticipant.new
    member.group_id = @group_id
    member.group_subtag_id = @subgroup_id
    member.participant_id = current_participant.id
    member.save!
    flash[:notice] = "You have joined #{@subgroup.tag}"
    redirect_to :action => :subgroups
  end
  
  def subgroup_unjoin
    #-- Current user leaving a subgroup
    @section = 'groups'
    @gsection = 'subgroups'
    @group_id = params[:id]
    @subgroup_id = params[:subgroup_id]
    @subgroup = GroupSubtag.find(@subgroup_id)
    member = GroupSubtagParticipant.where(:group_subtag_id=>@subgroup_id,:participant_id=>current_participant.id).first
    if member
      member.destroy
      flash[:notice] = "You have left #{@subgroup.tag}"      
    else
      flash[:alert] = "Couldn't join #{@subgroup.tag}"      
    end  
    redirect_to :action => :subgroups
  end   
  
  def subgroup_member_addremove
    @group_id = params[:id]
    @add_remove = params[:add_remove]
    @group_subtag_id = params[:group_subtag_id].to_i
    @marks = params[:mark]
    @active = params[:active]
    if @group_subtag_id > 0 and @marks.class == Array
      for participant_id in @marks
        submember = GroupSubtagParticipant.where(:group_subtag_id=>@group_subtag_id,:participant_id=>participant_id).first
        if submember and @add_remove == 'remove'
          submember.destroy
        elsif not submember and @add_remove == 'add'
          submember = GroupSubtagParticipant.new
          submember.group_id = @group_id
          submember.group_subtag_id = @group_subtag_id
          submember.participant_id = participant_id
          submember.save!
        end  
      end
    end
    redirect_to "/groups/#{@group_id}/members_admin?active=#{@active}"
  end  
  
  def subgroupadd
    #-- Show a pulldown for adding a subgroup to an item
    @group_id = params[:id]
    @group = Group.find_by_id(@group_id)
    @item_id = params[:item_id].to_i
    @item = Item.find_by_id(@item_id)
    render :partial=>'subgroupadd', :layout=>false
  end
  
  def subgroupsave
    #-- Saving a new subgroup for an item
    @group_id = params[:id]
    @group = Group.find_by_id(@group_id)
    @item_id = params[:item_id].to_i
    @item = Item.find_by_id(@item_id)
    @tag = params[:tag].to_s
    if @tag != ''
      @item.subgroup_list.add(@tag)
    end
    @item.save!
    if @item.is_first_in_thread and @item.subgroup_list.to_s != ''
      #-- Add it to any other messages in that thread, if it isn't already there. This is really if it was changed after the fact.
      subitems = Item.where(:first_in_thread=>@item.id).where(:is_first_in_thread=>false)
      for subitem in subitems
        subitem.subgroup_list = @item.subgroup_list
        subitem.save
      end
    end  
    render :text=>'ok', :layout=>false
  end     
  
  def subgroup_add_to
    #-- The admin adding a user to a subgroup tag from the subgroups page
    @group_id = params[:id]
    participant_id = params[:participant_id].to_i
    add_subgroup_id = params[:add_subgroup_id].to_i
    if participant_id > 0 and add_subgroup_id > 0
      member = GroupSubtagParticipant.where(:group_id=>@group_id).where(:group_subtag_id=>add_subgroup_id).where(:participant_id=>participant_id).first
      participant = Participant.find_by_id(participant_id)
      subgroup = GroupSubtag.find_by_id(add_subgroup_id)
      if member
        flash[:alert] = "User #{participant.name} was already in #{subgroup.tag}" 
      else        
        if participant and subgroup
          member = GroupSubtagParticipant.new
          member.group_id = @group_id
          member.group_subtag_id = add_subgroup_id
          member.participant_id = participant_id
          member.save!
          flash[:notice] = "User #{participant.name} has been added to #{subgroup.tag}" 
        else
          flash[:alert] = "Couldn't do that" 
        end    
      end     
    end
    redirect_to :action => :subgroups
  end  
  
  def invite
    #-- Invite screen
    @section = 'groups'
    @gsection = 'invite'
    @group_id = params[:id]
    @group = Group.includes(:group_participants=>:participant).find(@group_id)
    @messtext = ''
    @participant = Participant.includes(:idols).find(current_participant.id)  
    @members = Participant.order("first_name,last_name")  
    get_group_info
  end  
  
  def invitedo
    #-- Invite more members
    @section = 'groups'
    @gsection = 'invite'
    @group_id = params[:id]
    @group = Group.includes(:group_participants=>:participant).find(@group_id)
    get_group_info
    logger.info("groups#invitedo")  
    flash[:notice] = ''
    flash[:alert] = ''

    @follow_id = params[:follow_id].to_i
    @member_id = params[:member_id].to_i
    @new_text = params[:new_text].to_s
    @messtext = params[:messtext].to_s
    if @group.invite_template.to_s != ''
      @messtext += "<br><hr style=\"clear:both;\">\n" if @messtext != ''
      @messtext += @group.invite_template
    else       
      @messtext += render_to_string :partial=>"invite_default", :layout=>false
    end  

    @cdata = {}
    @cdata['current_participant'] = current_participant
    @cdata['group'] = @group if @group
    @cdata['group_logo'] = "http://#{BASEDOMAIN}#{@group.logo.url}" if @group.logo.exists?
    @cdata['logo'] = "http://#{BASEDOMAIN}#{@group.logo.url}" if @group.logo.exists?
    @cdata['domain'] = @group.shortname.to_s!='' ? "#{@group.shortname}.#{ROOTDOMAIN}" : BASEDOMAIN

    @member_id = @follow_id if @follow_id > 0

    if not ( @is_member and (@group.openness=='open' or @is_moderator) )
      flash[:alert] += "You're not allowed to invite new members<br>"
    elsif @member_id > 0
      #-- An existing member
      @recipient = Participant.find_by_id(@member_id)
      #@messtext += "<hr><a href=\"http://#{BASEDOMAIN}/participant/#{current_participant.id}/profile?auth_token=#{@recipient.authentication_token}\">#{current_participant.name}</a> has invited you to join the group <a href=\"http://#{BASEDOMAIN}/groups/#{@group.id}/view?auth_token=#{@recipient.authentication_token}\">#{@group.name}</a>"
      if @recipient
        invite1member
      else
        flash[:alert] += 'Recipient not found<br>'
      end  
      
    else
      #-- Some non-members, supposedly. But catch if some of them already are members.
      lines = @new_text.split(/[\r\n]+/)
      flash[:notice] += "#{lines.length} lines<br>"
      x = 0
      for line in lines do
        email = line.strip

        @recipient = Participant.find_by_email(email)
        if @recipient
          invite1member
        elsif not email =~ /^[[:alnum:]._%+-]+@[[:alnum:].-]+\.[[:alpha:]]{2,4}$/
          flash[:alert] += "\"#{email}\" doesn't look like a valid e-mail address<br>"  
        else
          @cdata['email'] = email
          @cdata['joinlink'] = "http://#{@cdata['domain']}/gjoin?group_id=#{@group.id}&amp;email=#{email}"

          if @messtext.to_s != ''
            template = Liquid::Template.parse(@messtext)
            html_content = template.render(@cdata)
          else
            html_content = "<p>You have been invited by #{current_participant.email_address_with_name} to join the group: #{@group.name}<br/>"
            html_content += "Go <a href=\"http://#{@group.shortname}.#{ROOTDOMAIN}/gjoin?group_id=#{@group.id}&email=#{email}\">here</a> to fill in your information and join.<br>"
            html_content += "</p>"            
          end
        
          subject = "#{current_participant.name} invites you to the #{@group.name} on InterMix"

          emailmess = SystemMailer.template("do-not-reply@intermix.org", email, subject, html_content, @cdata)

          logger.info("groups#invitedo delivering email to #{email}")
          begin
            emailmess.deliver
            flash[:notice] += "An invitation message was sent to #{email}<br>"
          rescue
            logger.info("groups#invitedo FAILED delivering email to #{email}")
            flash[:notice] += "Failed to send an invitation to #{email}<br>"
          end
        end

      end
      
    end
    redirect_to :action => :invite
  end
  
  def invite1member
    #-- Called from invitedo
    #-- Sending an invitation to one member
    group_participant = GroupParticipant.where("group_id=#{@group.id} and participant_id=#{@recipient.id}").first
    if not group_participant
      #-- Add them to the group as inactive if they aren't already there
      group_participant = GroupParticipant.create(:group_id=>@group.id, :participant_id=>@recipient.id,:active=>false,:status=>'invited')
    end
    if group_participant.active
      #-- If they're already there, and already active, no point in sending them an invite
      flash[:notice] += "#{@recipient.name} (#{@recipient.email}) is already a member of the group<br>"
    else      
      @recipient.ensure_authentication_token!
      @message = Message.new
      @message.to_participant_id = @recipient.id 
      @message.from_participant_id = current_participant.id
      @message.subject = "#{current_participant.name} invites you to the #{@group.name} on InterMix"
    
      @cdata['item'] = @item
      @cdata['recipient'] = @recipient     
      @cdata['participant'] = @recipient 
      @cdata['joinlink'] = "http://#{@cdata['domain']}/groups/#{@group.id}/invitejoin?auth_token=#{@recipient.authentication_token}"

      xmesstext = @messtext + "<hr><a href=\"http://#{BASEDOMAIN}/participant/#{current_participant.id}/profile?auth_token=#{@recipient.authentication_token}\">#{current_participant.name}</a> has invited you to join the group <a href=\"http://#{BASEDOMAIN}/groups/#{@group.id}/view?auth_token=#{@recipient.authentication_token}\">#{@group.name}</a>"

      if xmesstext.to_s != ''
        template = Liquid::Template.parse(xmesstext)
        html_content = template.render(@cdata)
      else  
        html_content = "<p>You have been invited to join the group: #{@group.name}<br/>"
        html_content += "</p>"
      end        
            
      @message.message = html_content
      @message.sendmethod = 'web'
      @message.sent_at = Time.now
      if @message.save
        if @recipient.private_email == 'instant'
          #-- Send as an e-mail. 
          @message.sendmethod = 'email'
          @message.emailit
        end  
        flash[:notice] += "An invitation message was sent to #{@recipient.name} (#{@recipient.email})"
      else
        logger.info("groups#invitedo Couldn't save message")  
        flash[:alert] += "There was a problem creating the invitation message for #{@recipient.name}."         
      end    
    end
  end
  
  def invitejoin
    #-- Link members go to to accept an invitation sent to them
    #-- They should already be logged in (with an authentication token), so we basically just join them, if they aren't already a member
    if not participant_signed_in?
      flash[:alert] = "You are not logged in"
      redirect_to '/'
      return
    end
    if params[:auth_token].to_s != '' and params[:auth_token] != current_participant.authentication_token
      flash[:alert] = "Seems like you were logged in as the wrong person. Try the link again."
      sign_out :participant
      redirect_to '/'
      return
    end
    @group_id = params[:id]
    @group = Group.find_by_id(@group_id)
    if not current_participant.groups.include?(@group)
      current_participant.groups << @group
      flash[:notice] = "You are now a member of this group"
    else
      group_participant = GroupParticipant.where(:group_id=>@group_id,:participant_id=>current_participant.id).first
      if not group_participant
        flash[:alert] = "Group membership not found"
        redirect_to '/'
        return
      elsif group_participant.active
        flash[:notice] = "You were already a member of this group"
      else
        group_participant.active = true
        group_participant.status = 'active'
        group_participant.save
        flash[:notice] = "You are now a member of this group"
      end  
    end  
    redirect_to :action => :forum
  end

  def import
    #-- Import members
    @section = 'groups'
    @gsection = 'import'
    @group_id = params[:id]
    @group = Group.includes(:group_participants=>:participant).find(@group_id)
    if flash[:messtext]
      @messtext = flash[:messtext]
    elsif @group.import_template.to_s.strip != ''
      @messtext = @group.import_template
    else       
      @messtext = render_to_string :partial=>"import_default", :layout=>false
    end  
    @subject = "You were added to a group"
    @participant = Participant.includes(:idols).find(current_participant.id)  
    @metamaps = Metamap.order("name")  
    get_group_info
  end  
  
  def importdo
    #-- Import members directly
    @section = 'groups'
    @gsection = 'import'
    @group_id = params[:id].to_i
    @group = Group.includes(:group_participants=>:participant).find(@group_id)
    logger.info("groups#importdo #{@group_id}")  
    @meta_1 = params[:meta_1].to_i
    @meta_2 = params[:meta_2].to_i
    @meta_3 = params[:meta_3].to_i
    flash[:notice] = ''
    flash[:alert] = ''

    @new_text = params[:new_text].to_s
    @subject = params[:subject].to_s
    @subject = "You were added to a group" if @subject == ''
    @messtext = params[:messtext].to_s

    metamapnames = {}
    metamapids = {}
    metamaprecs = Metamap.where(nil)
    for metamap in metamaprecs
      metamapnames[metamap.name.downcase] = metamap.id
      metamapids[metamap.id] = metamap.name
    end

    lines = @new_text.split(/[\r\n]+/)
    flash[:notice] += "#{lines.length} lines<br>"
    x = 0
    for line in lines do
      x += 1
      #next if x == 1
      #line = line.force_encoding("ISO-8859-1").encode("UTF-8").strip
      xarr = line.strip.split(';')

      email = xarr[0]
      if xarr.length < 4
        flash[:notice] += "#{email} incorrect number of fields (#{xarr.length}). Need 4+<br>"
        next
      end
      first_name = xarr[1]
      last_name = xarr[2]
      xcountry = xarr[3]

      flash[:notice] += "#{email}, #{first_name}, #{last_name}, #{xcountry}<br>"
      
      if email.to_s == ''
        next
      end

      participant = Participant.find_by_email(email)

      if participant
        # 'unconfirmed','active','inactive','never-contact','disallowed'
        if participant.status == 'active'
          flash[:notice] += "- already a member<br>"
        elsif participant.status == 'disallowed' or participant.status == 'never-contact' or participant.status == 'blocked'
          flash[:notice] += "- already a member, but blocked<br>"
        else    
          participant.status = 'active'
          participant.save
          flash[:notice] += "- unconfirmed member. Now set to confirmed<br>"
        end
        #password = "[as entered]"
        password = "<a href=\"http://#{@group.shortname.to_s!='' ? "#{@group.shortname}.#{ROOTDOMAIN}" : BASEDOMAIN}/participants/password/new\">Forgot your password?</a>"
      else
        participant = Participant.new
        participant.first_name = first_name
        participant.last_name = last_name
        participant.email = email
        if xcountry != ''
          #-- Check the country
          country = Geocountry.find_by_name(xcountry)
          country = Geocountry.find_by_iso(xcountry) if not country
          if country
            participant.country_code = country.iso
            participant.country_name = country.name
          end
        end
        password = ''
        3.times do
          conso = 'bcdfghkmnprstvw'[rand(15)]
          vowel = 'aeiouy'[rand(6)]
          password += conso +  vowel
          password += (1+rand(9)).to_s if rand(3) == 2
        end
        participant.password = password
        participant.forum_email = 'daily'
        participant.group_email = 'daily'
        participant.private_email = 'instant'  
        participant.status = 'active'
        participant.confirmation_token = Digest::MD5.hexdigest(Time.now.to_f.to_s + email)
        if participant.save
          flash[:notice] += "- added as member<br>"
        else
          flash[:notice] += "- problem adding as member<br>"
          next          
        end
      end
      
      #-- Add to group
      added_to_group = false
      group_participants = GroupParticipant.where("group_id=#{@group.id} and participant_id=#{participant.id}")
      if group_participants.length == 0
        GroupParticipant.create(:group_id=>@group.id, :participant_id=>participant.id,:active=>true,:status=>'active')
        flash[:notice] += "- added to the group<br>"
        added_to_group = true
      else
        flash[:notice] += "- already in the group<br>"
      end
      
      #-- Handle metatag fields      
      for pos in [4,5,6,7,8,9,10,11,12,13,14,15]
        if not xarr[pos] or xarr[pos].to_s == ''
          next
        end
        metamap_name = ""
        varval = xarr[pos].strip
        if varval.split(':').length > 1
          zarr = varval.split(':')
          metamap_name = zarr[0].strip.downcase
          if metamapnames[metamap_name]
            metamap_id = metamapnames[metamap_name]
          elsif metamap_name == 'Age' or metamap_name == 'age'
            metamap_id = 5
          elsif metamap_name == 'Gender' or metamap_name == 'gender'
            metamap_id = 3  
          else
            flash[:notice] += "- UNKNOWN META NAME: #{metamap_name}<br>"
            next
          end
          value = zarr[1].strip
        else
          metamap_id = 0
          value = varval
        end
        if metamap_id > 0
        elsif pos == 4
          metamap_id = params[:meta_1].to_i
        elsif pos == 5
          metamap_id = params[:meta_2].to_i
        elsif pos == 6
          metamap_id = params[:meta_3].to_i
        end
        if metamap_name == "" and metamapids[metamap_id]
          metamap_name = metamapids[metamap_id]
        end
        if metamap_id > 0
          metamap = Metamap.find_by_id(metamap_id)
          if not metamap
             flash[:notice] += "- UNKNOWN META ID: #{metamap_id}<br>"
          else
            if value.to_i > 0
              metamap_nodes = MetamapNode.where(:metamap_id=>metamap_id,:id=>value)              
            else
              metamap_nodes = MetamapNode.where(:metamap_id=>metamap_id,:name=>value)
            end
            if metamap_nodes.length > 0
              metamap_node_id = metamap_nodes[0].id
              #flash[:notice] += "- #{metamap_nodes.length} nodes matching metamap_id:#{metamap_id} name:#{value} Choosing:#{metamap_node_id}<br>"
              mnp = MetamapNodeParticipant.where(:metamap_id=>metamap_id,:participant_id=>participant.id).first
              if mnp
                mnp.metamap_node_id = metamap_node_id
                mnp.save
                flash[:notice] += "- updated meta #{metamap_name}: #{value}<br>"
              else
                MetamapNodeParticipant.create(:metamap_id=>metamap_id,:metamap_node_id=>metamap_node_id,:participant_id=>participant.id)
                flash[:notice] += "- added meta #{metamap_name}: #{value}<br>"
              end                  
            else
               flash[:notice] += "- UNKNOWN VALUE for #{metamap_name}: #{value}<br>"
            end
          end
        else
          flash[:notice] +=  "- UNKNOWN: #{value}<br>"
        end  
      end
      
      if @messtext.to_s != '' and added_to_group
        #-- Send an e-mail
        participant.ensure_authentication_token!
        @recipient = participant
        @message = Message.new
        @message.to_participant_id = participant.id 
        @message.from_participant_id = current_participant.id
        @message.subject = @subject
        
        cdata = {}
        cdata['item'] = @item
        cdata['recipient'] = participant     
        cdata['participant'] = participant 
        cdata['current_participant'] = current_participant
        cdata['group'] = @group if @group
        cdata['group_logo'] = "http://#{BASEDOMAIN}#{@group.logo.url}" if @group.logo.exists?
        cdata['domain'] = @group.shortname.to_s!='' ? "#{@group.shortname}.#{ROOTDOMAIN}" : BASEDOMAIN
        if @group.logo.exists? then
         cdata['logo'] = "#{BASEDOMAIN}#{@group.logo.url}"
        else
          cdata['logo'] = @logo if @logo
        end
        cdata['password'] = password
        
        cdata['template'] = 'system_generic'

        template = Liquid::Template.parse(@messtext)
        html_content = template.render(cdata)
        
        #@messtext += "<hr>username: #{participant.email}<br>password: #{password}"
        @message.message = html_content
        @message.sendmethod = 'web'
        @message.sent_at = Time.now
        @message.group_id = @group.id
        if @message.save
          if participant.private_email == 'instant' and not participant.no_email
            #-- Send as an e-mail. 
            @message.sendmethod = 'email'
            #@message.mail_template = 'message_system'
            @message.mail_template = 'message_import'
            @message.emailit
          end  
          flash[:notice] += "- message was sent<br>"
        else
          logger.info("groups#importdo Couldn't save message")  
          flash[:alert] += "- problem sending message"         
        end
      end
    end   
    flash[:messtext] = @messtext
    redirect_to :action => :import
  end

  def join
    #-- Join a group
    @group_id = params[:id].to_i
    @group = Group.find(@group_id)
    if @group.openness == 'open'
      @group_participant = GroupParticipant.where("group_id = ? and participant_id = ?",@group_id,current_participant.id).first
      if @group_participant
        flash[:notice] = 'You are already a member of this group'
      else  
        @group_participant = GroupParticipant.new(:moderator => false, :active => true, :status => 'active')
        @group_participant.active = true
        @group_participant.group_id = @group.id
        @group_participant.participant_id = current_participant.id
        @group_participant.save
        flash[:notice] = 'You have joined this group'
      end
    else
      flash[:notice] = 'This group is not open to join'
    end
    redirect_to :action => :view 
    update_prefix
  end
  
  def unjoin
    #-- Leave a group
    @group_id = params[:id].to_i
    @group = Group.find(@group_id)
    @group_participant = GroupParticipant.where("group_id = ? and participant_id = ?",@group_id,current_participant.id).first
    if @group_participant
      #-- Remove subgroup membership too
      group_subtag_participants = GroupSubtagParticipant.where(:group_id=>@group_id,:participant_id=>current_participant.id)
      for gsp in group_subtag_participants
        gsp.destroy
      end
      #-- And the group membership itself
      @group_participant.destroy
      flash[:notice] = "You have now left this group"     
    else
      flash[:notice] = "You don't seem to be a member of this group"     
    end  
    redirect_to :action => :view 
  end   
  
  def forum
    #-- Show most recent items that this user is allowed to see
    @section = 'groups'
    @gsection = 'forum'
    @from = 'group'
    @group_id = params[:id].to_i
    @group = Group.includes(:owner_participant).find(@group_id)
    @exp_item_id = (params[:exp_item_id] || 0).to_i
    @has_subgroups = (@group.group_subtags.length > 0)
    @tag = params[:tag].to_s
    @subgroup = params.include?(:subgroup) ? params[:subgroup].to_s : 'my'
    get_group_info
    @dialog_id = -1
    @limit_group = @group
    
    if not session[:has_required]
      session[:has_required] = current_participant.has_required
      if not session[:has_required]
        #redirect_to :controller => :profiles, :action=>:edit
        redirect_to '/me/profile/meta'
        return
      end
    #elsif current_participant.new_signup
    #  redirect_to :controller => :profiles, :action=>:edit
    #  return
    end
    
    
    if @group and @group.message_visibility == 'private' and not @is_member
      #-- Messages are private, and they aren't a member
      redirect_to "/groups/#{@group_id}/view"
      return
    end  
    
    if participant_signed_in? and current_participant.forum_settings
      set = current_participant.forum_settings
    else
      set = {}
    end    
    @sortby = params[:sortby] || set['sortby'] || "items.id desc"
    @perscr = (params[:perscr] || set['perscr'] || 25).to_i
    @page = ( params[:page] || 1 ).to_i
    @page = 1 if @page < 1

    if @sortby[0,5] == 'meta:'
       @sortby = 'items.id desc'
    end

    @show_meta = false
    
    @threads = params[:threads] || set['threads'] || 'flat'
    if @threads == 'flat' or @threads == 'tree' or @threads == 'root'
      @rootonly = true
    end

    if true
      #-- Get the records, while adding up the stats on the fly

      #@items, @itemsproc, @extras = Item.list_and_results(@group,nil,@period_id,0,@posted_meta,@rated_meta,@rootonly,@sortby,current_participant,true,0,'','','','',0,'','',0,@tag,@subgroup)

    else
      #-- The old way

      @items = Item.where(nil)
      @items = @items.where("items.group_id = ?", @group_id)    
      if @threads == 'flat' or @threads == 'tree'
        #- Show original message followed by all replies in a flat list
        @items = @items.where("is_first_in_thread=1")
      end
      @items = @items.includes([:group,:participant,:period,{:participant=>{:metamap_node_participants=>:metamap_node}},:item_rating_summary])
      @items = @items.joins("left join ratings on (ratings.item_id=items.id and ratings.participant_id=#{current_participant.id})")
      @items = @items.select("items.*,ratings.participant_id as hasrating,ratings.approval,ratings.interest")
    
      @items = @items.order(@sortby)
      @items = @items.paginate :page=>@page, :per_page => @per_page    
    
    end
    
    #@items = @items.paginate :page=>@page, :per_page => @perscr  
        
    @groupsin = GroupParticipant.where("participant_id=#{current_participant.id}").select("distinct(group_id),moderator").includes(:group)

    @dialogsin = DialogParticipant.where("participant_id=#{current_participant.id}").includes(:dialog)      
    @dialogsin = DialogGroup.where("group_id=#{@group_id}").includes(:dialog)      

    #-- Make a list of the groups subgroups with the current users subgroups first.
    all_subgroups = @group.group_subtags.collect{|s| s.tag}
    users_subgroups = @group.mysubtags(current_participant).sort
    other_subgroups = (all_subgroups - users_subgroups).sort
    @all_subgroups = users_subgroups + other_subgroups

    if current_participant.new_signup
      @new_signup = true
      current_participant.new_signup = false
      current_participant.save
    #elsif session[:new_signup].to_i == 1
    #  @new_signup = true
    #  session[:new_signup] = 0
    elsif params[:new_signup].to_i == 1
      @new_signup = true
    end

    update_last_url
    update_prefix
  end   

  def period_edit
    @group_id = params[:id].to_i
    @group = Group.find(@group_id)
    get_group_info
    @period_id = params[:period_id].to_i
    if @period_id == 0
      @period = Period.new(:group_id=>@group_id,:group_dialog=>'group')
    else
      @period = Period.find(@period_id)
    end
  end
  
  def period_save
    @group_id = params[:id].to_i
    @group = Group.find(@group_id)
    @period_id = params[:period_id].to_i    
    if @period_id > 0
      @period = Period.find(@period_id)
    else
      @period = Period.new()
      @period.group_id = @group_id
      @period.group_dialog = 'group'
    end  
    @period.startdate = params[:period][:startdate]
    @period.enddate = params[:period][:enddate]
    @period.name = params[:period][:name]
    @period.save!
    redirect_to :action=>:admin
  end
  
  def subtag_edit
    @group_id = params[:id].to_i
    @group = Group.find(@group_id)
    get_group_info
    @group_subtag_id = params[:group_subtag_id].to_i
    if @group_subtag_id == 0
      @group_subtag = GroupSubtag.new(:group_id=>@group_id)
    else
      @group_subtag = GroupSubtag.find(@group_subtag_id)
    end
  end
  
  def subtag_save
    @group_id = params[:id].to_i
    @group = Group.find(@group_id)
    @group_subtag_id = params[:group_subtag_id].to_i    
    if @group_subtag_id > 0
      @group_subtag = GroupSubtag.find(@group_subtag_id)
    else
      @group_subtag = GroupSubtag.new()
      @group_subtag.group_id = @group_id
    end  
    @group_subtag.tag = params[:group_subtag][:tag].gsub(',',' ')[0,50]
    @group_subtag.description = params[:group_subtag][:description]
    @group_subtag.selfadd = params[:group_subtag][:selfadd]
    @group_subtag.save!
    redirect_to :action=>:admin
  end

  def dialog_settings
    #-- Show/edit the specifics for the group dialog membership
    @group_id = params[:id].to_i
    @group = Group.find(@group_id)
    get_group_info
    @dialog_id = params[:dialog_id].to_i
    @dialog = Dialog.find_by_id(@dialog_id)
    @dialog_group = DialogGroup.where("group_id=#{@group_id} and dialog_id=#{@dialog_id}").first  
  end
  
  def dialog_settings_save
    @group_id = params[:id].to_i
    @group = Group.find(@group_id)
    
    @dialog_group_id = params[:dialog_group_id]
    @dialog_group = DialogGroup.find_by_id(@dialog_group_id)
    @dialog_group.signup_template = params[:dialog_group][:signup_template]
    @dialog_group.confirm_template = params[:dialog_group][:confirm_template]
    @dialog_group.confirm_email_template = params[:dialog_group][:confirm_email_template]
    @dialog_group.confirm_welcome_template = params[:dialog_group][:confirm_welcome_template]
    @dialog_group.save!
    redirect_to :action=>:admin
  end
  
  def remove_dialog
    #-- Leave a discussion
    @group_id = params[:id].to_i
    @group = Group.find(@group_id)
    @dialog_group_id = params[:dialog_group_id]
    @dialog_group = DialogGroup.find_by_id(@dialog_group_id)
    @dialog_group.destroy
    flash[:notice] = 'Group has been removed from the discussion'
    redirect_to :action=>:admin
  end  
  
  def apply_dialog
    #-- Apply to be a member of a discussion
    @group_id = params[:id].to_i
    @group = Group.find(@group_id)
    @dialog_id = params[:apply_dialog_id].to_i
    @dialog = Dialog.find_by_id(@dialog_id)
    @dialog_group = DialogGroup.new(:group_id=>@group_id,:dialog_id=>@dialog_id,:active=>false,:apply_status=>'apply',:apply_by=>current_participant.id,:apply_at=>Time.now)
    @dialog_group.save!
    
    for participant in @group.moderators
      #-- Let all moderators of the group know that somebody has filed the application
      @message = Message.new
      @message.subject = "#{@dialog.name} discussion"
      @message.message = "<p>#{current_participant.name} has applied for the group #{@group.name} to join the discussion #{@dialog.name}</p><p>You're receiving this because you're a moderator in #{@group.name}</p>"
      @message.to_participant_id = participant.id
      @message.from_participant_id = 0
      @message.sendmethod = 'web'
      @message.sent_at = Time.now
      if @message.save        
        @message.sendmethod = 'email'
        @message.emailit
      end
    end
    
    #-- Let the discussion administrators know
    @dgroup_id = @dialog.group_id
    @dgroup = Group.find_by_id(@dgroup_id)
    if @dgroup
      for participant in @dgroup.moderators
        #-- Let all moderators of the group owning the discussion know that somebody has filed the application
        @message = Message.new
        @message.subject = "#{@group.name} wants to join #{@dialog.name}"
        @message.message = "<p>#{current_participant.name} has applied for the group #{@group.name} to join the discussion #{@dialog.name}</p><p>Somebody needs to approve the application before the membership becomes active.</p><p>You're receiving this because you're a moderator in #{@dgroup.name} which administers the #{@dialog.name} discussion</p>"
        @message.to_participant_id = participant.id
        @message.from_participant_id = 0
        @message.sendmethod = 'web'
        @message.sent_at = Time.now
        if @message.save        
          @message.sendmethod = 'email'
          @message.emailit
        end
      end
    end
        
    redirect_to :action=>:admin
  end
  
  def add_moderator
    #-- Add a new moderator. Called from admin screen. Must already be a group member
    @group_id = params[:id].to_i
    @group = Group.find(@group_id)
    @participant_id = params[:participant_id].to_i
    if @participant_id > 0
      @group_participant = GroupParticipant.where(:group_id=>@group_id,:participant_id=>@participant_id).first
      if @group_participant
        @group_participant.active = true
        @group_participant.moderator = true
        @group_participant.save!
      end
    end   
    redirect_to :action=>:admin
  end
  
  def group_participant_edit
    #-- Edit a membership in a group, for example to change active or moderator status
    @section = 'groups'
    @is_member = true
    @is_moderator = true
    @group_id = params[:id].to_i
    @group = Group.find(@group_id)
    @participant_id = params[:participant_id]
    @members_active = params[:active].to_i
    @group_participant = GroupParticipant.includes(:participant).where(:group_id=>@group_id,:participant_id=>@participant_id).first
    @participant = @group_participant.participant    
  end
  
  def group_participant_save
    #-- Save changes to a group membership
    @group_id = params[:id].to_i
    @group = Group.find_by_id(@group_id)
    members_active = params[:members_active].to_i
    @group_participant_id = params[:group_participant_id]
    @group_participant = GroupParticipant.find_by_id(@group_participant_id)
    active_before = @group_participant.active
    status_before = @group_participant.status    
    @group_participant.active = params[:group_participant][:active]
    @group_participant.status = params[:group_participant][:status]
    @group_participant.moderator = params[:group_participant][:moderator]
    @group_participant.save!
    @participant = @group_participant.participant
    domain = @group.shortname.to_s != "" ? "#{@group.shortname}.#{ROOTDOMAIN}" : BASEDOMAIN
    
    if status_before == 'applied' and @group_participant.status == 'active'
      #-- They've been accepted to the group. Let them know.
      html_content = "<p>Your membership of #{@group.name} has been accepted! You can now go to: <a href=\"http://#{domain}/groups/#{@group.id}/forum?auth_token=#{@participant.authentication_token}\">http://#{domain}/groups/#{@group.id}/forum</a> to see the messages.</p>"
      email = @participant.email
      msubject = "[#{@group.shortname}] You're now a member of #{@group.name}"
      email = SystemMailer.generic(SYSTEM_SENDER, @participant.email_address_with_name, msubject, html_content, {})
      begin
        logger.info("groups#group_participant_save delivering email to #{recipient.id}:#{recipient.name}")
        email.deliver
        message_id = email.message_id
      rescue
        logger.info("groups#group_participant_save problem delivering email to #{recipient.id}:#{recipient.name}")
      end
    elsif status_before == 'applied' and @group_participant.status == 'denied'
      #-- They were denied membership in the group
      html_content = "<p>Sorry, your membership of #{@group.name} has not been accepted.</p>"
      email = @participant.email
      msubject = "[#{@group.shortname}] #{@group.name} membership application"
      email = SystemMailer.generic(SYSTEM_SENDER, @participant.email_address_with_name, msubject, html_content, {})
      begin
        logger.info("groups#group_participant_save delivering email to #{recipient.id}:#{recipient.name}")
        email.deliver
        message_id = email.message_id
      rescue
        logger.info("groups#group_participant_save problem delivering email to #{recipient.id}:#{recipient.name}")
      end
    end
    
    flash[:notice] = "Group member settings updated"
    url = "/groups/#{@group_id}/members_admin"
    if members_active >= 0
      url += "?active=#{@members_active}"
    end
    redirect_to url
  end
    
  def get_default
    #-- Return a particular default template, e.g. invite, member, import
    which = params[:which]
    render :partial=>"#{which}_default", :layout=>false
  end

  def get_dg_default
    #-- Return a particular default template for a dialog_group
    #-- That will be either the main one used by the discussion, or if not defined, the default discussion template
    which = params[:which]
    @dialog_group_id = params[:dialog_group_id]
    @dialog_group = DialogGroup.find_by_id(@dialog_group_id)
    @group = Group.find_by_id(@dialog_group.group_id)
    @dialog = Dialog.find_by_id(@dialog_group.dialog_id)
    if @dialog.send("#{which}_template").to_s != ''
      render :text=>@dialog.send("#{which}_template"), :layout=>false
    else  
      render :partial=>"dialogs/#{which}_default", :layout=>false
    end  
  end
  
  def test_template
    #-- Show a template with the liquid macros filled in
    which = params[:which]
    @group_id = params[:id]
    @group = Group.find_by_id(@group_id)
    @domain = (@group and @group.shortname.to_s!='') ? "#{@group.shortname}.#{ROOTDOMAIN}" : BASEDOMAIN
    @logo = "http://#{BASEDOMAIN}#{@group.logo.url}" if @group.logo.exists?
    @participant = current_participant
    @email = @participant.email
    @name = @participant.name
    @countries = Geocountry.order(:name).select([:name,:iso])
    @meta = []
    metamaps = @group.metamaps
    for metamap in metamaps
      #m = OpenStruct.new
      m = {}
      m['id'] = metamap.id
      m['name'] = metamap.name
      m['val'] = params["meta_#{metamap.id}"].to_i
      m['nodes'] = [{'id'=>0,'name'=>'* choose *'}]
      MetamapNode.where(:metamap_id=>m['id']).order(:sortorder,:name).each do |node|
        #n = OpenStruct.new
        n = {}
        n['id'] = node.id
        n['name'] = node.name
        m['nodes'] << n
      end
      @meta << m
    end
    
    cdata = {}
    cdata['group'] = @group
    cdata['dialog'] = @dialog if @dialog
    cdata['group_logo'] = "http://#{BASEDOMAIN}#{@group.logo.url}" if @group and @group.logo.exists?
    cdata['dialog_logo'] = "http://#{BASEDOMAIN}#{@dialog.logo.url}" if @dialog and @dialog.logo.exists?
    cdata['dialog_group'] = @dialog_group if @dialog_group
    cdata['participant'] = @participant
    cdata['current_participant'] = @current_participant
    cdata['recipient'] = @participant
    cdata['domain'] = @domain
    cdata['password'] = '[#@$#$%$^]'
    cdata['confirmlink'] = "http://#{@domain}/front/confirm?code=#{@participant.confirmation_token}&group_id=#{@group_id}"
    cdata['logo'] = @logo if @logo
    cdata['countries'] = @countries
    cdata['meta'] = @meta
    cdata['message'] = '[Custom message]'    
    cdata['subject'] = '[Subject line]'
      
    if @group.send("#{which}_template").to_s != ""
      template_content = render_to_string(:text=>@group.send("#{which}_template"),:layout=>false)
    else
      template_content = render_to_string(:partial=>"#{which}_default",:layout=>false)
    end      
    template = Liquid::Template.parse(template_content)
    render :text => template.render(cdata), :layout=>'front'
  end
  
  def twitauth
    #-- Try to get an authorization to post group items to some twitter account
    #-- I could also use omniauth or devise. That is, if I knew how.
    #-- http://oauth.rubyforge.org/
    #-- http://cbpowell.wordpress.com/2010/10/12/twitter-oauth-and-ruby-on-rails-integrated-cookbook-style-in-the-console/
    #-- http://cbpowell.wordpress.com/2011/03/17/twitter-oauth-and-ruby-on-rails-integrated-cookbook-style-in-the-console-updated-for-twitter-1-0/
    #-- http://groups.google.com/group/ruby-twitter-gem/browse_thread/thread/29d587637afe28eb#
    #-- http://stakeventures.com/articles/2008/02/23/developing-oauth-clients-in-ruby
    #-- http://philsturgeon.co.uk/news/2010/11/using-omniauth-to-make-twitteroauth-api-requests
    #-- http://blog.brijeshshah.com/integrate-twitter-oauth-in-your-rails-application/comment-page-1/
     
    @group_id = params[:id] 
     
    #-- Acquire a request token
    @request_token = GroupsController.twitconsumer.get_request_token(:oauth_callback => "http://#{BASEDOMAIN}/groups/#{@group_id}/twitcallback")
    session[:rtoken] = @request_token.token
    session[:rsecret] = @request_token.secret
    authorize_url = @request_token.authorize_url    # "http://api.twitter.com/oauth/authorize?oauth_token=your_request_token"
    ## http://twitter.com/oauth/request_token/oauth/authorize?oauth_token=2H3SG76EYVJkYSaxBvJ0oK1zWoofhd2nSUsSD4VAk1Y

    #use OmniAuth::Strategies::Twitter, TWITTER_CONSUMER_KEY, TWITTER_CONSUMER_SECRET
    
    logger.info("groups#twitauth rtoken:#{session[:rtoken]} rsecret:#{session[:rsecret]} authorize_url:#{authorize_url}")
    
    #-- Send use to authorization
    #redirect_to '/auth/twitter'
    redirect_to authorize_url 
        
  end  

  def twitcallback
    #-- Callback from Twitter, after somebody authorizes themselves
    #-- This is where we get the access keys
    #-- http://cbpowell.wordpress.com/2011/03/17/twitter-oauth-and-ruby-on-rails-integrated-cookbook-style-in-the-console-updated-for-twitter-1-0/
    #-- http://dev.twitter.com/pages/auth

    # params: {"oauth_token"=>"cT4jP3LWUd7RFAoVADtR9Oec4GSA2TppjVxufC6BMM", "oauth_verifier"=>"wqxxDrsBaILlGTc8CSnyvAkAdZYqt6wuik5EUdfLzSI", "controller"=>"profiles", "action"=>"twitcallback"}

    @group_id = params[:id] 
    
    oauth_token = params[:oauth_token]   # Same as the request token we sent
    oauth_verifier = params[:oauth_verifier]   # What we need for the next top
    
    @request_token = OAuth::RequestToken.new(GroupsController.twitconsumer, session[:rtoken], session[:rsecret])
    
    #-- Exchange the request token for an access token

    #atoken, asecret = oauth.authorize_from_request(rtoken, rsecret, your_pin_here)
    
    # Exchange the request token for an access token.
    @access_token = @request_token.get_access_token(:oauth_verifier => oauth_verifier)
    
    if @access_token.token.to_s != ''
      #-- We have an authorized user, save the information to the database.
      @group = Group.find_by_id(@group_id)
      @group.twitter_oauth_token = @access_token.token
      @group.twitter_oauth_secret = @access_token.secret
      @group.save!    
      flash[:notice] = "Authentication succeeded"
    else
      flash[:notice] = "Authentication failed"
    end
    redirect_to "/groups/#{@group_id}/admin"
    
    #@response = GroupsController.twitconsumer.request(:get, '/account/verify_credentials.json',@access_token, { :scheme => :query_string })
    #case @response
    #when Net::HTTPSuccess
    #  user_info = JSON.parse(@response.body)
    #  unless user_info['screen_name']
    #    flash[:notice] = "Authentication failed"
    #    redirect_to :action =>:index
    #    return
    #  end
    #  # Redirect to the edit page
    #  redirect_to "/groups/#{@group_id}/admin"
    #else      
    #  logger.info("groups#twitcallback Failed to get user info via OAuth")
    #  # The user might have rejected this application. Or there was some other error during the request.
    #  flash[:notice] = "Authentication failed"
    #  redirect_to "/groups/#{@group_id}/admin"
    #end  
  end  
  

  protected
  
  def self.twitconsumer
    #-- Provide a consumer object, for Twitter access
    OAuth::Consumer.new(TWITTER_CONSUMER_KEY, TWITTER_CONSUMER_SECRET, {:site=>"http://api.twitter.com/"})   
  end
 
  def update_prefix
    #-- Update the current group, and the prefix and base url
    return if not @group
    before_group_id = session[:group_id] if session[:group_id]
    before_dialog_id = session[:dialog_id] if session[:dialog_id]
    #if @is_member
      session[:group_id] = @group.id
      session[:group_name] = @group.name
      session[:group_prefix] = @group.shortname
      session[:group_is_member] = @is_member
    #else
    #  session[:group_id] = 0
    #  session[:group_name] = ''
    #  session[:group_prefix] = ''
    #end
    session[:cur_prefix] = @group.shortname
    session[:dialog_id] = 0
    session[:dialog_name] = ''
    session[:dialog_prefix] = ''
    if session[:cur_prefix] != ''
      session[:cur_baseurl] = "http://" + session[:cur_prefix] + "." + ROOTDOMAIN    
    else
      session[:cur_baseurl] = "http://" + BASEDOMAIN    
    end
    session.delete(:list_sortby) if session.include?(:list_sortby) 
    session.delete(:slider_period_id) if session.include?(:slider_period_id)
    if participant_signed_in? and ( session[:group_id] != before_group_id or session[:dialog_id] != before_dialog_id )
       current_participant.last_group_id = session[:group_id] if session[:group_id]
       current_participant.last_dialog_id = session[:dialog_id] if session[:dialog_id]
       current_participant.save
    end    
  end
  
  def redirect_subdom
    #-- If we're not using the right subdomain, redirect
    if request.get? and session[:cur_prefix] != '' and Rails.env == 'production' and (request.host == BASEDOMAIN or request.host == ROOTDOMAIN)
      host_should_be = "#{session[:cur_prefix]}.#{ROOTDOMAIN}"
      if request.host != host_should_be
        redirect_to "http://#{host_should_be}#{request.fullpath}"
      end
    end
  end
  
  def get_group_info
    #-- Look up a few pieces of information about the group and group member, for menus, etc.
    @group_participant = GroupParticipant.where("group_id = ? and participant_id = ?",@group.id,current_participant.id).first
    if @group.id == GLOBAL_GROUP_ID and not @group_participant
      #-- If it is the global townhall, add them if they somehow aren't there
      @group_participant = GroupParticipant.create(group_id: GLOBAL_GROUP_ID, participant_id: current_participant.id, active: true, status: 'active')
    end
    @is_member = @group_participant ? true : false
    @is_moderator = ((@group_participant and @group_participant.moderator) or current_participant.sysadmin)
    @has_dialog = (@group.active_dialogs.length > 0)
  end
  
  def group_params
    params.require(:group).permit(:is_global, :logo, :name, :shortname, :description, :shortdesc, :instructions, :visibility, :message_visibility, :openness, :moderation, :twitter_post, :twitter_username, :twitter_oauth_token, :twitter_oauth_secret, :twitter_hash_tag, :has_mail_list, :front_template, :member_template, :invite_template, :import_template, :signup_template, :confirm_template, :confirm_email_template, :confirm_welcome_template, :alt_logins, :required_meta, :tweet_approval_min, :tweet_what, :tweet_subgroups, :is_network)
  end
  

end
