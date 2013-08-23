require 'will_paginate/array'

class ItemsController < ApplicationController

  layout "front"
  before_filter :authenticate_participant!, :except=>[:pubgallery,:view]

  def index
    list  
  end  

  def list
    #-- Return the items to show on the page
    @from = params[:from] || ''
 
    @sortby = params[:sortby] || "items.id desc"
    @perscr = params[:perscr].to_i || 25
    @threads = params[:threads] || 'flat'
    @limit_group_id = (params[:limit_group_id] || 0).to_i
    @dialog_id = (params[:dialog_id] || 0).to_i
    @period_id = (params[:period_id] || 0).to_i
    @posted_by_country_code = (params[:posted_by_country_code] || '').to_s
    @posted_by_admin1uniq = (params[:posted_by_admin1uniq] || '').to_s
    @posted_by_metro_area_id = (params[:posted_by_metro_area_id] || 0).to_i
    @rated_by_country_code = (params[:rated_by_country_code] || '').to_s
    @rated_by_admin1uniq = (params[:rated_by_admin1uniq] || '').to_s
    @rated_by_metro_area_id = (params[:rated_by_metro_area_id] || 0).to_i
    @page = ( params[:page] || 1 ).to_i
    @page = 1 if @page < 1
    @perscr = 25 if @perscr < 1    
    @dialog = Dialog.find_by_id(@dialog_id) if @dialog_id > 0
    if @period_id > 0
      @period = Period.find_by_id(@period_id)
    elsif @dialog and @dialog.active_period
      @period = @dialog.active_period
      #@period_id = @dialog.active_period.id
    end    
    
    if @threads == 'flat' or @threads == 'tree' or @threads == 'root'
      @rootonly = true
    end

    if @from == 'wall'
      @posted_by = ( params[:id] || current_participant.id ).to_i
      @participant = Participant.find(@posted_by)
    else
      @posted_by = 0  
    end   

    @show_meta = false
    if @sortby == 'default'
      sortby = 'items.id desc'
    elsif @sortby[0,5] == 'meta:' and @from == 'dialog'
      metamap_id = @sortby[5,10].to_i
      sortby = "metamap_nodes.name"
      #@items = @items.where("metamap_nodes.metamap_id=#{metamap_id}")
      #@show_meta = true
    elsif @sortby[0,5] == 'meta:'
      sortby = 'items.id desc'
      @sortby = sortby
    else
      sortby = @sortby
    end
    
    @posted_meta={}
    @rated_meta={}
    params.each do |var,val|
      if var[0,18] == 'posted_by_metamap_'
        metamap_id = var[18,].to_i
        if params["posted_by_metamap_#{metamap_id}"].to_i > 0
          @posted_meta[metamap_id] = params["posted_by_metamap_#{metamap_id}"].to_i
        end
      elsif var[0,17] == 'rated_by_metamap_'
        metamap_id = var[17,].to_i
        if params["rated_by_metamap_#{metamap_id}"].to_i > 0
          @rated_meta[metamap_id] = params["rated_by_metamap_#{metamap_id}"].to_i
        end
      end
    end
            
    if true
      #-- Get the records, while adding up the stats on the fly

      @items, @itemsproc = Item.list_and_results(@limit_group_id,@dialog_id,@period_id,@posted_by,@posted_meta,@rated_meta,@rootonly,@sortby,current_participant.id,true,0,'','',@posted_by_country_code,@posted_by_admin1uniq,@posted_by_metro_area_id,@rated_by_country_code,@rated_by_admin1uniq,@rated_by_metro_area_id)
      
      #logger.info("items_controller#list @items: #{@items.inspect}")
      
    else
      # old way
        
      @items = Item.scoped
      #@items = @items.tagged_with(params[:tags]) if params[:tags].to_s != ''
      #@items = @items.where(:group_id => params[:group_id]) if params[:group_id].to_i > 0
      #@items = @items.includes([:group,:participant,:ratings,:item_rating_summary]).where("ratings.participant_id=#{current_participant.id} or ratings.participant_id is null")
      if @group_id > 0
        @items = @items.where("items.group_id = ?", @group_id)    
      end
      if @dialog_id > 0
        @items = @items.where("items.dialog_id = ?", @dialog_id)    
      elsif @dialog_id < 0
        #-- This is when we particularly don't want any discussion messages
        @items = @items.where("items.dialog_id=0 or items.dialog_id is null")  
      end
      if @period_id > 0
        @items = @items.where("items.period_id = ?", @period_id)    
      end
      #@threads = 'flat' if @threads == ''
      if @threads == 'flat' or @threads == 'tree' or @threads == 'root'
        #- Show original message followed by all replies in a flat list
        @items = @items.where("is_first_in_thread=1")
      end
    
      if @from == 'wall'
        @participant_id = ( params[:id] || current_participant.id ).to_i
        @participant = Participant.find(@participant_id)
        @items = @items.where(:posted_by => @participant_id)
      elsif @from == 'forum' and @group_id == 0 and @dialog_id == 0
        @items = @items.where(:posted_to_forum => true)  
      end   

      @items = @items.includes([:dialog,:group,:period,{:participant=>{:metamap_node_participants=>:metamap_node}},:item_rating_summary])
      @items = @items.joins("left join ratings on (ratings.item_id=items.id and ratings.participant_id=#{current_participant.id})")
      @items = @items.select("items.*,ratings.participant_id as hasrating,ratings.approval as rateapproval,ratings.interest as rateinterest,'' as explanation")

      if @dialog_id > 0
        #-- For a dialog we might need to filter by metamap for poster and/or rater
        @metamaps = Metamap.joins(:dialogs).where("dialogs.id=#{@dialog_id}")
        for metamap in @metamaps
          if params["posted_by_metamap_#{metamap.id}"].to_i != 0
            posted_by_metamap_node_id = params["posted_by_metamap_#{metamap.id}"].to_i
            #logger.info("items#list Posted by metamap #{metamap.id}: #{posted_by_metamap_node_id}")
            @items = @items.joins("inner join metamap_node_participants p_mnp_#{metamap.id} on (p_mnp_#{metamap.id}.participant_id=items.posted_by and p_mnp_#{metamap.id}.metamap_id=#{metamap.id} and p_mnp_#{metamap.id}.metamap_node_id=#{posted_by_metamap_node_id})")
            #@items = @items.where("p_mnp_#{metamap.id}.participant_id=#{current_participant.id} and p_mnp_#{metamap.id}.metamap_id=#{metamap.id} and p_mnp_#{metamap.id}.metamap_node_id=#{posted_by_metamap_node_id}")
          end
          if params["rated_by_metamap_#{metamap.id}"].to_i != 0
            rated_by_metamap_node_id = params["rated_by_metamap_#{metamap.id}"].to_i
            #@items = @items.joins("join ratings r_#{metamap_id} on (items.id=ratings.item_id)")
            @items = @items.where("(select count(*) from ratings r_#{metamap.id} inner join participants r_p_#{metamap.id} on (r_#{metamap.id}.participant_id=r_p_#{metamap.id}.id) inner join metamap_node_participants r_mnp_#{metamap.id} on (r_mnp_#{metamap.id}.participant_id=r_p_#{metamap.id}.id and r_mnp_#{metamap.id}.metamap_node_id=#{rated_by_metamap_node_id}) where r_#{metamap.id}.item_id=items.id)>0")
          end
        end
      end

    end

    
    #@show_extra = @items.to_sql
    #logger.info("items#list SQL: #{@items.to_sql}")
    
    #if @sortby == 'default'
    #  @dialog = Dialog.find_by_id(@dialog_id)
    #  @items = Item.custom_item_sort(@items, @page, @perscr, current_participant.id, @dialog).paginate :page=>@page, :per_page => @perscr
    #else
    #  @items = @items.order(sortby)
    #  @items = @items.paginate :page=>@page, :per_page => @perscr   
    #end
    
    @items = @items.paginate :page=>@page, :per_page => @perscr  

    if participant_signed_in?
      current_participant.forum_settings = {'sortby'=>sortby,'perscr'=>@perscr,'threads'=>@threads,'group_id'=>@group_id,'dialog_id'=>@dialog_id}
      current_participant.save
    end  
    
    #-- Try to figure out if the user is allowed to post. Mainly to know which message to show them if there are no messages.
    @can_post = false
    if @from == 'dialog'      
      if @dialog.current_period.to_i > 0
        @previous_messages_period = Item.where("posted_by=? and dialog_id=? and period_id=? and (reply_to is null or reply_to=0)",current_participant.id,@dialog.id,@dialog.current_period.to_i).count      
      else
        @previous_messages_period = 0
      end  
      @previous_messages = Item.where("posted_by=? and dialog_id=? and (reply_to is null or reply_to=0)",current_participant.id,@dialog.id).count
      if session[:group_is_member] and ((@dialog.current_period.to_i > 0 and (@dialog.active_period.max_messages.to_i == 0 or @previous_messages_period < @dialog.active_period.max_messages.to_i)) or (@dialog.current_period.to_i == 0 and (@dialog.max_messages.to_i == 0 or @previous_messages < @dialog.max_messages.to_i))) and @dialog.settings_with_period["posting_open"]
        @can_post = true
      end
    elsif @from == 'group'
      if @is_member
        @can_post = true        
      end
    elsif @from == 'wall'
      if @posted_by == current_participant.id
        @can_post = true
      end
    end
    
    render :partial=>'list', :layout=>false  
  end  
  
  def new
    #-- screen for a new item, either new thread or a reply
    @from = params[:from] || ''
    @reply_to = params[:reply_to].to_i
    @item = Item.new(:media_type=>'text',:link=>'http://',:reply_to=>@reply_to)
    @items_length = params[:items_length].to_i
    if params[:group_id].to_i > 0
      @item.group_id = params[:group_id] 
    else
      @item.group_id = 0      
    end
    if params[:dialog_id].to_i > 0
      @dialog_id = params[:dialog_id].to_i
      @item.group_id = session[:group_id].to_i if @item.group_id == 0
    else
      @dialog_id = 0      
    end
    if @dialog_id > 0
      @dialog = Dialog.find_by_id(@dialog_id)
      @dialog_name = (@dialog ? @dialog.name : '???')
      @item.period_id = @dialog.current_period if @dialog
    end  
    @item.dialog_id = @dialog_id
    @max_characters = @dialog ? @dialog.max_characters : 0    
    @max_words = @dialog ? @dialog.max_words : 0    
    
    if @item.reply_to.to_i > 0
      @item.is_first_in_thread = false 
      @olditem = Item.find_by_id(@item.reply_to)
      if @olditem
        @item.first_in_thread = @olditem.first_in_thread
        if @olditem.subject.to_s != '' and @olditem.subject[0,3] != 'Re:' and @olditem.subject[0,3] != 're:'
          #@item.subject = "Re: #{@olditem.subject}"[0,48]  
          @item.subject = "Re: #{@olditem.subject}"  
        elsif @olditem.subject != ''
          @item.subject = @olditem.subject 
        end
        @item.group_id = @olditem.group_id if @item.group_id.to_i == 0 and @olditem.group_id.to_i > 0
        @item.dialog_id = @olditem.dialog_id if @olditem.dialog_id.to_i > 0
        if @item.dialog_id.to_i > 0
          @dialog = Dialog.find_by_id(@item.dialog_id)
          @dialog_name = (@dialog ? @dialog.name : '???')
          @item.period_id = @dialog.current_period if @dialog
        end  
      end
    else
      if @dialog and @dialog.settings_with_period["default_message"].to_s != ''
        @item.html_content = @dialog.settings_with_period["default_message"]
      end    
    end   

    @groupsin = GroupParticipant.where("participant_id=#{current_participant.id}").includes(:group).all       
    @dialogsin = DialogParticipant.where("participant_id=#{current_participant.id}").includes(:dialog).all  
    @dialoggroupsin = []
    if @dialog
      #-- The user might be a member of several of the groups participating in the current dialog, if any
      for group1 in @dialog.groups
        for group2 in @groupsin
          if group2.group and group2.group.id == group1.id
            @dialoggroupsin << group1
          end
        end
      end
    end   

    #-- Don't allow sending to group or dialog one isn't a member of
    if @item.group_id > 0
      ingroup = false
      for gp in @groupsin
        ingroup = true if gp.group and gp.group_id == @item.group_id
      end 
      if not ingroup
        @item.group_id = 0 
        if @item.reply_to.to_i == 0
          render :text=>"<p>You're not a member of that group</p>", :layout=>false
          return
        end
      end
    end
    #if @item.dialog_id > 0
    #  indialog = false
    #  for dp in @dialogsin
    #    indialog = true if dp.dialog_id == @item.dialog_id
    #  end
    #  @item.dialog_id = 0 if not indialog
    #end

    if @item.group_id > 0
      @group = Group.find_by_id(@item.group_id)
      @send_to = "G#{@item.group_id}"
      @send_to_name = 'Group: ' + (@group ? @group.name : '???')
    #elsif @item.dialog_id > 0
    #  @dialog = Dialog.find_by_id(@item.dialog_id)
    #  @send_to = "D#{@item.dialog_id}"
    #  @send_to_name = 'Dialog: ' + (@dialog ? @dialog.name : '???')
    #  @dialog_name = (@dialog ? @dialog.name : '???')
    elsif current_participant.item_to_forum
      @send_to = 'all'  
      @send_to_name = '*everybody forum / my wall*'
    else
      @send_to = 'wall'
      @send_to_name = '*my wall*'
    end    
    
    #-- Check if they're not allowed to post a new root message, based on dialog/period settings, etc.
    if @dialog and @item.reply_to.to_i == 0
      if @dialog.active_period and @dialog.active_period.max_messages.to_i > 0
        @previous_messages_period = Item.where("posted_by=? and dialog_id=? and period_id=? and (reply_to is null or reply_to=0)",current_participant.id,@dialog.id,@dialog.current_period.to_i).count      
        if @previous_messages_period >= @dialog.active_period.max_messages.to_i
          render :text=>"<p>You've already reached your maximum number of threads for this period</p>", :layout=>false
          return
        end
      end  
      if @dialog.max_messages.to_i > 0
        @previous_messages = Item.where("posted_by=? and dialog_id=? and (reply_to is null or reply_to=0)",current_participant.id,@dialog.id).count
        if @previous_messages >= @dialog.max_messages.to_i
          render :text=>"<p>You've already reached your maximum number of threads for this discussion</p>", :layout=>false
          return
        end
      end
    end
    
    render :partial=>'edit', :layout=>false
  end  

  def edit
    #-- screen for a editing a message
    @from = params[:from] || ''
    @item_id = params[:id]
    @item = Item.find(@item_id)
    @items_length = params[:items_length].to_i

    prepare_edit

    if @item.group_id > 0
      @send_to = "G#{@item.group_id}"
      @send_to_name = 'Group: ' + (@group ? @group.name : '???')
    elsif @item.dialog_id > 0
      @send_to = "D#{@item.dialog_id}"
      @send_to_name = 'Dialog: ' + (@dialog ? @dialog.name : '???')
    elsif @item.posted_to_forum
      @send_to = 'all'  
      @send_to_name = '*everybody forum / my wall*'
    else
      @send_to = 'wall'
      @send_to_name = '*my wall*'
    end   
    render :partial=>'edit', :layout=>false
  end  
  
  def prepare_edit
    #-- Get a few things ready for editing or adding an item
    @group = Group.find_by_id(@item.group_id) if @item.group_id > 0
    if @item.dialog_id.to_i > 0
      @dialog_id = @item.dialog_id
      @dialog = Dialog.find_by_id(@item.dialog_id)
      @dialog_name = (@dialog ? @dialog.name : '???')
    end  
    @groupsin = GroupParticipant.where("participant_id=#{current_participant.id}").includes(:group).all       
    @dialogsin = DialogParticipant.where("participant_id=#{current_participant.id}").includes(:dialog).all  
    @dialoggroupsin = []
    if @dialog
      #-- The user might be a member of several of the groups participating in the current dialog, if any
      for group1 in @dialog.groups
        for group2 in @groupsin
          if group2.group.id == group1.id
            @dialoggroupsin << group1
          end
        end
      end
    end   
    @max_characters = @dialog ? @dialog.max_characters : 0
    @max_words = @dialog ? @dialog.max_words : 0
  end
    
  def create
    @from = params[:from] || ''
    @item = Item.new(params[:item])
    @item.link = '' if @item.link == 'http://'
    @item.item_type = 'message'
    @item.posted_by = current_participant.id
    
    if @item.reply_to.to_i > 0
      @item.is_first_in_thread = false 
      @olditem = Item.find_by_id(@item.reply_to)
      if @olditem
        if @olditem.first_in_thread.to_i > 0
          @item.first_in_thread = @olditem.first_in_thread
        else
          @item.first_in_thread = @item.reply_to
        end 
        if @olditem.first_in_thread_group_id.to_i > 0
          @item.first_in_thread_group_id = @olditem.first_in_thread_group_id
        else  
          @item.first_in_thread_group_id = @olditem.group_id
        end  
        if current_participant.id != @olditem.posted_by
          @olditem.edit_locked = true
          @olditem.save
        end
      end
    else
      @item.is_first_in_thread = true 
      @item.first_in_thread_group_id = @item.group_id
    end    
    logger.info("items#create by #{@item.posted_by}")

    if not itemvalidate
      logger.info("items#create by #{@item.posted_by}: failing validation: #{@xmessage}")
      flash.now[:alert] = @xmessage
    end
    logger.info("items#create item is validated")
    
    itemprocess
    logger.info("items#create item has been processed")
    
    if @item.dialog_id > 0 and @dialog
      #-- Various controls set by either a discussion or by a focus group in a discussion
      # open for posting?
      if not @dialog.settings_with_period["posting_open"]
        flash.now[:alert] = "Sorry, this discussion is not open for new messages"
      end      
      #if @item.reply_to.to_i == 0 and @dialog.settings_with_period["max_messages"].to_i > 0
      #  max_messages = @dialog.settings_with_period["max_messages"].to_i
      #  previous_messages = Item.where("posted_by=? and dialog_id=? and reply_to is null",current_participant.id,@dialog.id).count
      #  if previous_messages >= max_messages
      #    flash.now[:alert] = "Sorry, you can only post #{max_messages} message#{max_messages > 1 ? 's' : ''} here"
      #  end
      #  if @item.period_id > 0 and @dialog.active_period and @dialog.active_period.max_messages.to_i > 0
      #    previous_messages_period = Item.where("posted_by=? and dialog_id=? and period_id=? and (reply_to is null or reply_to=0)",current_participant.id,@dialog.id,@dialog.current_period.to_i).count      
      #    if previous_messages_period >= @dialog.active_period.max_messages.to_i
      #      flash.now[:alert] = "Sorry, you can only post #{@dialog.active_period.max_messages} message#{max_messages > 1 ? 's' : ''} here"
      #    end
      #  end
      #end
      plain_content = view_context.strip_tags(@item.html_content.to_s).strip
      if @item.reply_to.to_i > 0 and not @dialog.settings_with_period["allow_replies"]
        flash.now[:alert] = 'Sorry, replies are not permitted here'
      elsif @dialog.settings_with_period["required_subject"] and @item.subject.to_s.strip == ""
        flash.now[:alert] = "A subject is required"
      elsif @item.is_first_in_thread and @dialog.settings_with_period["max_characters"].to_i > 0 and plain_content.length > @dialog.settings_with_period["max_characters"]
        flash.now[:alert] = "That's too many characters"
      elsif @item.is_first_in_thread and @dialog.settings_with_period["max_words"].to_i > 0 and plain_content.scan(/(\w|-)+/).size > @dialog.settings_with_period["max_words"]
        flash.now[:alert] = "That's too many words"
      end
    end
        
    if flash[:alert] or flash.now[:alert]
      prepare_edit
      render :partial=>'edit', :layout=>false
      return
    
    elsif @item.save
      if @item.is_first_in_thread
        @item.first_in_thread = @item.id    
        @item.save    
      end  
      #if current_participant.twitter_post and current_participant.twitter_username.to_s !='' and current_participant.twitter_oauth_token.to_s != ''
      #  #-- Post to Twitter
      #  begin
      #    Twitter.configure do |config|
      #      config.consumer_key = TWITTER_CONSUMER_KEY
      #      config.consumer_secret = TWITTER_CONSUMER_SECRET
      #      config.oauth_token = current_participant.twitter_oauth_token
      #      config.oauth_token_secret = current_participant.twitter_oauth_secret
      #    end
      #    Twitter.update(@item.short_content)
      #  rescue
      #    logger.info("items#create problem posting to twitter")
      #  end  
      #end
      ##-- E-mail to everybody who's asked for it
      #@item.emailit
      
      current_participant.update_attribute(:has_participated,true) if not current_participant.has_participated
      #render :text=>'Item was successfully created.', :layout=>false
      results = {'error'=>false,'message'=>"Item was successfully created.",'item_id'=>@item.id}        
      render :json=>results, :layout=>false
      
    end  
  end  
  
  def update
    @from = params[:from] || ''
    @item = Item.find(params[:id])
    @item.link = '' if @item.link == 'http://'
    
    @item.assign_attributes(params[:item])

    if not itemvalidate
      #render :text=>@xmessage, :layout=>false
      #results = {'error'=>true,'message'=>@xmessage,'item_id'=>@item.id}
      #render :json=>results, :layout=>false
      #return
      flash.now[:alert] = @xmessage
    end
    if flash[:alert] or flash.now[:alert]
      prepare_edit
      render :partial=>'edit', :layout=>false
      return
    end
    #if @item.update_attributes(params[:item])
      itemprocess
      @item.save
      #showmess = (@error_message.to_s != '') ? @error_message : "Item was successfully updated."
      if @error_message.to_s != ''
        results = {'error'=>true,'message'=>@error_message,'item_id'=>@item.id}
      else
        results = {'error'=>false,'message'=>"Item was successfully updated.",'item_id'=>@item.id}        
      end  
      render :json=>results, :layout=>false
      #render :text=>showmess, :layout=>false
    #end   
  end  
  
  def view
    #-- Show an individual post
    @from = params[:from] || 'individual'
    @item_id = params[:id]
    @item = Item.includes([:dialog,:group,{:participant=>{:metamap_node_participants=>:metamap_node}},:item_rating_summary])
    
    @item = @item.joins("left join ratings r_has on (r_has.item_id=items.id and r_has.participant_id=#{current_participant.id})") if participant_signed_in?
    @item = @item.select("items.*,r_has.participant_id as hasrating,r_has.approval as rateapproval,r_has.interest as rateinterest,'' as explanation") if participant_signed_in?    
    @item = @item.find_by_id(@item_id)
    
    @item.voting_ok(participant_signed_in? ? current_participant.id : 0)

    @group_id,@dialog_id = get_group_dialog_from_subdomain

    @group_id = @item.group_id
    if @group_id.to_i > 0
      @group = Group.includes(:owner_participant).find(@group_id)
      if participant_signed_in?
        @group_participant = GroupParticipant.where("group_id = ? and participant_id = ?",@group.id,current_participant.id).find(:first)
        @is_member = @group_participant ? true : false
        @is_moderator = @group_participant and @group_participant.moderator
      else
        @is_member = false
        @is_moderator = false
      end
      #@from = "group"
      session[:group_is_member] = @is_member
      session[:group_name] = @group.name
      session[:group_prefix] = @group.shortname
    end
    session[:group_id] = @group_id

    @dialog_id = @item.dialog_id
    if @dialog_id.to_i > 0
      @dialog = Dialog.includes(:groups).find_by_id(@dialog_id)   
      @groups = @dialog.groups if @dialog and @dialog.groups
      @periods = @dialog.periods if @dialog and @dialog.periods
      if participant_signed_in?
        @groupsin = GroupParticipant.where("participant_id=#{current_participant.id}").includes(:group).all
        dialogadmin = DialogAdmin.where("dialog_id=? and participant_id=?",@dialog_id, current_participant.id)
        @is_admin = (dialogadmin.length > 0)
        @previous_messages = Item.where("posted_by=? and dialog_id=? and (reply_to is null or reply_to=0)",current_participant.id,@dialog_id).count
      else
        @is_admin = false
        @previous_messages = []
      end
      #@from = "dialog"
    end
    session[:dialog_id] = @dialog_id
    
    if @dialog_id.to_i > 0 and @group_id.to_i > 0 and participant_signed_in? and not @is_member
      #-- If the reader isn't a member of the group the message is posted under, see if he's a member of another group in the discussion
      for group in @dialog.groups
        group_participant = GroupParticipant.where("group_id = ? and participant_id = ?",@group_id,current_participant.id).find(:first)
        if group_participant and group_participant.group
          @group_id = group.id
          @group = group
          @is_member = true
          session[:group_id] = @group_id
          session[:group_is_member] = @is_member
          break
        end
      end
    end
    
    @period_id = 0
    @posted_by = 0
    @posted_meta={}
    @rated_meta={}
    @rootonly = false
    @sortby = "items.id desc"
    @posted_by_country_code = ''
    @posted_by_admin1uniq = ''
    @posted_by_metro_area_id = 0
    @rated_by_country_code = ''
    @rated_by_admin1uniq = ''
    @rated_by_metro_area_id = 0
    
    #-- Even though we're only showing one item, we still need to get the context, with the ratings, etc.
    if participant_signed_in?
      @items, @itemsproc = Item.list_and_results(@group_id,@dialog_id,@period_id,@posted_by,@posted_meta,@rated_meta,@rootonly,@sortby,current_participant.id,true,0,'','',@posted_by_country_code,@posted_by_admin1uniq,@posted_by_metro_area_id,@rated_by_country_code,@rated_by_admin1uniq,@rated_by_metro_area_id)
    else
      @items, @itemsproc = Item.list_and_results(@group_id,@dialog_id,@period_id,@posted_by,@posted_meta,@rated_meta,@rootonly,@sortby,0,true,0,'','',@posted_by_country_code,@posted_by_admin1uniq,@posted_by_metro_area_id,@rated_by_country_code,@rated_by_admin1uniq,@rated_by_metro_area_id)
    end

    update_last_url
    #update_prefix

    render :action=>'item'
  end  
  
  def thread
    #-- Show the whole thread, based on an item
    @from = params[:from] || 'thread'
    @item_id = params[:id]
    @item = Item.includes([:dialog,:group,{:participant=>{:metamap_node_participants=>:metamap_node}},:item_rating_summary]).find(@item_id)
    
    @dialog_id = @item.dialog_id
    if @dialog_id.to_i > 0
      @dialog = Dialog.includes(:groups).find_by_id(@dialog_id)   
      @groups = @dialog.groups if @dialog and @dialog.groups
      @periods = @dialog.periods if @dialog and @dialog.periods
      @groupsin = GroupParticipant.where("participant_id=#{current_participant.id}").includes(:group).all
      dialogadmin = DialogAdmin.where("dialog_id=? and participant_id=?",@dialog_id, current_participant.id)
      @is_admin = (dialogadmin.length > 0)
      @previous_messages = Item.where("posted_by=? and dialog_id=? and (reply_to is null or reply_to=0)",current_participant.id,@dialog.id).count
    end
    
    @group_id = @item.group_id
    if @group_id.to_i > 0
      @group = Group.includes(:owner_participant).find(@group_id)
      @group_participant = GroupParticipant.where("group_id = ? and participant_id = ?",@group.id,current_participant.id).find(:first)
      @is_member = @group_participant ? true : false
      @is_moderator = @group_participant and @group_participant.moderator
    end

    if participant_signed_in? and current_participant.forum_settings
      set = current_participant.forum_settings
    else
      set = {}
    end    

    @first_item_id = @item.first_in_thread
    @first_item = Item.find(@first_item_id )

    @period_id = 0
    @posted_by = 0
    @posted_meta={}
    @rated_meta={}
    @rootonly = false
    @sortby = "items.id desc"
    @posted_by_country_code = ''
    @posted_by_admin1uniq = ''
    @posted_by_metro_area_id = 0
    @rated_by_country_code = ''
    @rated_by_admin1uniq = ''
    @rated_by_metro_area_id = 0
    
    #-- Even though we're only showing one item, we still need to get the context, with the ratings, etc.
    @items, @itemsproc = Item.list_and_results(@group_id,@dialog_id,@period_id,@posted_by,@posted_meta,@rated_meta,@rootonly,@sortby,current_participant.id,true,0,'','',@posted_by_country_code,@posted_by_admin1uniq,@posted_by_metro_area_id,@rated_by_country_code,@rated_by_admin1uniq,@rated_by_metro_area_id)

    update_last_url
    #update_prefix

    render :action=>'thread'
  end
  
  def rate
    #-- rate an item
    @from = params[:from] || ''
    intapp = params[:intapp]
    item_id = params[:id].to_i
    vote = params[:vote].to_i
    
    item = Item.includes(:dialog,:group).find_by_id(item_id)

    group_id = item.group_id.to_i
    dialog_id = item.dialog_id.to_i
    
    #-- Check if they're allowed to rate it
    if not item.voting_ok(current_participant.id)
      render :text=>'', :layout=>false
      return
    end
    
    #-- See if that user already has rated that item, or create a new rating if they haven't
    rating = Rating.find_or_initialize_by_item_id_and_participant_id_and_rating_type(item_id,current_participant.id,'AllRatings')
    
    if intapp == 'int'
      rating.interest = vote
    elsif intapp == 'app'
      rating.approval = vote
    end    
    
    rating.save!
    
    item_rating_summary = ItemRatingSummary.find_or_create_by_item_id(item_id)
    if current_participant.id == 6
      item_rating_summary.recalculate(false,item.dialog)      
    else
      item_rating_summary.recalculate(false,item.dialog)
    end
    if (dialog_id > 0 and rating.dialog_id.to_i == 0) or (group_id > 0 and rating.group_id.to_i == 0)
      rating.group_id = group_id
      rating.dialog_id = dialog_id
      if dialog_id > 0
        dialog = Dialog.find_by_id(dialog_id)
        rating.period_id = dialog.current_period if dialog
      end
      rating.save
    end
    
    item.approval = item_rating_summary.app_average
    item.interest = item_rating_summary.int_average
    item.value = item_rating_summary.value
    item.controversy = item_rating_summary.controversy
    item.edit_locked = true if current_participant.id != item.posted_by
    item.save
    
    render :text=>vote, :layout=>false
  end  
  
  def get_summary
    @item_id = params[:id]
    items = Item.where(:id=>@item_id).includes(:item_rating_summary,:dialog)
    @item = items[0]
    @item.item_rating_summary.recalculate(false,@item.dialog)
    render :partial=>"rating_summary", :layout=>false, :locals=>{:item=>@item}
  end
  
  def play
    #-- return the code for an embedded item, so it can be played
    @from = params[:from] || ''
    @item_id = params[:id]
    @item = Item.find(@item_id)
    render :text=>@item.embed_code, :layout=>false
  end  
  
  def pubgallery
    #-- Public gallery
    @group_id = 8
    @items = Item.where("items.group_id=#{@group_id} and items.has_picture=1 and items.media_type='picture'").includes(:participant).order("items.id desc").limit(12)
  end  
  
  protected 
  
  def itemvalidate
    @xmessage = '' if not @xmessage
    dialog_id = params[:item][:dialog_id].to_i
    dialog = Dialog.find_by_id(dialog_id) if dialog_id
    html_content = params[:item][:html_content].to_s.strip
    subject = params[:item][:subject].to_s.strip
    plain_content = view_context.strip_tags(html_content)
    plain_content.gsub!('&nbsp;','')
    plain_content.strip!
    if params[:js_message_length]
      message_length = params[:js_message_length].to_i
    else
      message_length = plain_content.length
    end
    if plain_content == '' and @item.media_type =='text' and ((dialog and dialog.settings_with_period["required_message"]) or subject != '')
      @xmessage += "Please include at least a brief message<br>"
    elsif @item.short_content == ''
      @xmessage += "Please include at least a short message<br>"
    elsif @item.is_first_in_thread and dialog and dialog.settings_with_period["max_characters"].to_i > 0 and message_length > dialog.settings_with_period["max_characters"]  
      @xmessage += "The maximum message length is #{dialog.settings_with_period["max_characters"]} characters<br>"
    elsif @item.is_first_in_thread and dialog and dialog.settings_with_period["max_words"].to_i > 0 and plain_content.scan(/(\w|-)+/).size > dialog.settings_with_period["max_words"]
      @xmessage += "That's too many words"
    elsif dialog and dialog.settings_with_period["required_subject"] and subject.to_s == '' and html_content.gsub(/<\/?[^>]*>/, "").strip != ''
      @xmessage += "Please choose a subject line<br>"
    #elsif subject != '' and ((subject[0,3] != 'Re:' and subject.length > 48) or subject.length > 52)
    #  @xmessage += "Maximum 48 characters for the subject line, please<br>"        
    else
      return true
    end  
    #@xmessage = "<p style=\"color:#f00;text-align:center;font-weight:bold;font-size:16px;border:1px solid #f00;padding:10px;\"><br>#{@xmessage}</p>"
    #@xmessage = "<p style=\"color:#f00;\"><br>#{@xmessage}</p>"
    return false
  end
  
  def itemprocess
    logger.info("items#itemprocess media_type:#{@item.media_type}") 
    
    @send_to = params[:send_to]
    #if @send_to[0] == 'G'
    #  @item.group_id = @send_to[1,].to_i
    #else  
    #  @item.group_id = params[:item][:group_id].to_i
    #end  
    #@item.group_id = 0 if @item.group_id.to_i < 0
    #if @send_to[0] == 'D'
    #  @item.dialog_id = @send_to[1,].to_i
    #else  
    #  @item.dialog_id = params[:item][:dialog_id].to_i
    #end  
    
    @item.group_id = params[:item][:group_id].to_i
    @item.group_id = 0 if @item.group_id.to_i < 0
    @item.dialog_id = params[:item][:dialog_id].to_i
    @item.dialog_id = 0 if @item.dialog_id.to_i < 0
    if @item.dialog_id > 0
      @dialog = Dialog.find_by_id(@item.dialog_id)
      @item.group_id = @dialog.group_id.to_i if @dialog and @item.group_id.to_i == 0
    end
    
    if @send_to == 'wall'
      @item.posted_to_forum = false
    else
      @item.posted_to_forum = true      
    end    
    
    if @item.media_type == 'video' or @item.media_type == 'audio'
      if @item.link.to_s != ''
        response = get_embedly(@item.link)
        if response
          @item.oembed_response = response
          if response['html'] and response['html'].to_s != ''
            @item.embed_code = response['html']
          end  
        end
      end
    elsif @item.media_type == 'picture'
      itempicupload
    else
      logger.info("items#itemprocess before clean:#{@item.html_content.inspect}") 
      @item.html_content = Sanitize.clean(@item.html_content, 
        :elements => ['a', 'p', 'br', 'u', 'b', 'em', 'strong', 'ul', 'li', 'h1', 'h2', 'h3','table','tr','tbody','td','img'],
        :attributes => {'a' => ['href'], 'img' => ['src', 'alt', 'width', 'height', 'align', 'vspace', 'hspace', 'style']},
        :protocols => {'a' => {'href' => ['http', 'https', 'mailto', :relative]}, 'img' => {'src'  => ['http']} },
        :allow_comments => false,
        :output => :html,
        :remove_contents => ['style']
      )
      #-- Make all links open a new window
      logger.info("items#itemprocess before regex:#{@item.html_content.inspect}") 
      @item.html_content.gsub!(/a href/im,'a target="_blank" href')
      logger.info("items#itemprocess after regex:#{@item.html_content.inspect}") 
    end
  end  
  
  def itempicupload
    #-- Put any uploaded or grabbed picture in the right place
    @participant_id = current_participant.id
    got_file = false
    tempfilepath = "/tmp/#{current_participant.id}_#{Time.now.to_i}"
    `rm -f #{tempfilepath}`    
    logger.info("items#itempicupload tempfilepath:#{tempfilepath}")
    
    if params[:uploadfile] and params[:uploadfile].original_filename.to_s != ""
      #-- We got an uploaded file
      original_filename = params[:uploadfile].original_filename.to_s
      logger.info("items#itempicupload uploaded file:#{original_filename}")      
      f = File.new(tempfilepath, "wb")
      f.write params[:uploadfile].read
      f.close
    elsif params[:photo_id].to_i > 0
      #-- Use one of the user's photos
      tempfilepath = "#{DATADIR}/photos/#{@participant_id}/#{params[:photo_id]}.jpg"     
    elsif @item.link != ''
      #-- Grab file from url
      logger.info("items#itempicupload grabbing:#{@item.link}")      
      #-- Parse the URL into its component parts
      begin
        uri = URI.parse(@item.link)
      rescue
        @error_message = "The URL isn't right: " + $!.to_s
        return
      end
      if uri.query.to_s != ""
        path = uri.path + '?' + uri.query
      else
        path = uri.path
      end  
      #-- Prepare a request object  
      req = Net::HTTP::Get.new(path)
      #-- Set headers
      req.add_field("User-Agent", "Mozilla/5.0 (Macintosh; U; Intel Mac OS X 10_6_2; en-US) AppleWebKit/533.2 (KHTML, like Gecko) Chrome/5.0.342.7 Safari/533.2")
      #-- Make the actual http request
      response = nil
      jstart = Time.now.to_i
      begin
        Timeout::timeout(10) do 
          response = Net::HTTP.new(uri.host, uri.port).start do |http|
            http.request(req)
          end
        end 
      rescue Timeout::Error
        @error_message = "Timeout for URL: " + $!.to_s
        return      
      rescue
        @error_message = "Error in http call: " + $!.to_s
        return      
      end
      if response
        #@http_result = "#{response.code} #{response.message}"
        #print "#{@camera.id} Response Code: #{response.code} #{response.message}\n" if @debug
        #response.each {|key,val| printf "%-14s: %-40.40s\n", key, val}
        logger.info("items#itempicupload response code:#{response.code}")      
        if response.code.to_i != 200
          @error_message = "HTTP failure when accessing URL: " + $!.to_s
          return
        end  
      else
        @error_message = "No response when accessing URL\n"
        return
      end
      f = File.new(tempfilepath, "wb")
      f.write response.body
      f.close
    else
      logger.info("items#itempicupload apparently didn't get anything: #{params[:uploadfile].inspect}")      
    end    
       
    if not File.exist?(tempfilepath)
      return
    end  
      
    if not (flash[:alert] or flash.now[:alert])
      if not @item.id  
        @item.save
      end

      @item.add_image(tempfilepath)
    end
    
    `rm -f #{tempfilepath}`
    
    
  end

  def update_prefix
    #-- Update the current dialog, and the prefix and base url 
    logger.info("items#update_prefix")   
    if @group
      if @is_member
        session[:group_id] = @group.id
        session[:group_name] = @group.name
        session[:group_prefix] = @group.shortname
        session[:group_is_member] = true
      else
        session[:group_id] = 0
        session[:group_name] = ''
        session[:group_prefix] = ''
        session[:group_is_member] = false
      end
      session[:cur_prefix] = @group.shortname
      session[:dialog_id] = 0
      session[:dialog_name] = ''
      session[:dialog_prefix] = ''
      if session[:cur_prefix] != ''
        session[:cur_baseurl] = "http://" + session[:cur_prefix] + "." + ROOTDOMAIN    
      else
        session[:cur_baseurl] = "http://" + BASEDOMAIN    
      end
    end
    if @dialog
      session[:dialog_id] = @dialog.id
      session[:dialog_name] = @dialog.name
      session[:dialog_prefix] = @dialog.shortname
      if session[:dialog_prefix].to_s != '' and session[:group_prefix].to_s != ''
        session[:cur_prefix] = session[:dialog_prefix] + '.' + session[:group_prefix]
      elsif session[:group_prefix].to_s != ''
        session[:cur_prefix] = session[:group_prefix]
      elsif session[:dialog_prefix].to_s != ''
        session[:cur_prefix] = session[:dialog_prefix]
      end
      if session[:cur_prefix] != ''
        session[:cur_baseurl] = "http://" + session[:cur_prefix] + "." + ROOTDOMAIN    
      else
        session[:cur_baseurl] = "http://" + BASEDOMAIN    
      end
    end 
  end
    
end
