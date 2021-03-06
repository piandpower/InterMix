# encoding: utf-8

class MessageMailer < ActionMailer::Base
  #-- For sending messages, i.e. internal mail that doesn't go on the forum
  
  default :from => SYSTEM_SENDER

  def contacts(subject,message,email,cdata={})
    #-- For messages about follows, friends, etc
    @message = message
    @cdata = cdata 
    headers["InterMix-ID"] = "m#{cdata['message'].id}" if cdata['message']  
    mail(
      :to => email,
      :subject => (subject ? subject : "InterMix Contacts")
    )
  end  

  def individual(subject,message,email,cdata={})
    #-- Message to send to a participant, usually a private message
        
    @message = message
    @cdata = cdata
    
    #for att in cdata['attachments']
    #  attachments[ att['filename'] ] = att['content'] 
    #end
    
    headers["InterMix-ID"] = "m#{cdata['message'].id}" if cdata['message']
    
    mail(
      :to => email,
      :subject => (subject ? subject : "A private InterMix message")
    )

    logger.info("MessageMailer#generic message created")
    
  end  
  
  def group(subject,message,email,cdata={})
    #-- For messages to groups
    @message = message
    @cdata = cdata 
    headers["InterMix-ID"] = "m#{cdata['message'].id}" if cdata['message']   
    mail(
      :to => email,
      :subject => (subject ? subject : "InterMix Group Message")
    )
  end  

  def system(subject,message,email,cdata={})
    #-- For plain system messages, or import messages, or similar
    @message = message
    @cdata = cdata 
    headers["InterMix-ID"] = "m#{cdata['message'].id}" if cdata['message']   
    mail(
      :to => email,
      :subject => (subject ? subject : "InterMix Group Message")
    )
  end  

  def import(subject,message,email,cdata={})
    #-- For formatted messages from a template, to somebody added to a group
    @message = message
    @cdata = cdata 
    headers["InterMix-ID"] = "m#{cdata['message'].id}" if cdata['message']   
    mail(
      :to => email,
      :subject => (subject ? subject : "InterMix Group Message")
    )
  end  
  

end
