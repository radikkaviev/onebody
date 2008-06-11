class MessagesController < ApplicationController
  
  def new
    if params[:to_person_id] 
      # private message
      @person = Person.find(params[:to_person_id])
      @message = Message.new(:to_person_id => @person.id, :subject => params[:subject], :body => params[:body]) # TODO: not sure if this params stuff is needed any more
      render :action => 'new_private_message'
    else
      raise 'Unknown message type.'
    end
  end
  
  def create
    if params[:wall_id]
      create_wall_message(params[:wall_id])
    elsif params[:to_person_id]
      create_private_message(params[:to_person_id])
    elsif params[:group_id]
      create_group_message(params[:group_id])
    else
      raise 'Unknown message type.'
    end
  end
  
  private
  
  def create_wall_message(wall_id)
    @person = Person.find(wall_id)
    if @logged_in.can_see?(@person) and @person.wall_enabled?
      @person.wall_messages.create! params[:message].merge(:subject => 'Wall Post', :person => @logged_in)
      respond_to do |format|
        format.html { redirect_to person_path(@person) + '#wall' }
        format.js do
          @messages = @person.wall_messages.find(:all, :limit => 10)
          render :partial => 'walls/wall'
        end
      end
    else
      render :text => 'Wall not found.', :status => 404
    end
  end
  
  def create_private_message(to_person_id)
    @person = Person.find(to_person_id)
    if @person.email
      attributes = params[:message].merge(:person => @logged_in, :to => @person)
      if params[:preview]
        @msg = @message = Message.new(attributes) # TODO: get rid of this @msg at some point
        preview = render_to_string(:file => File.join(RAILS_ROOT, 'app/views/notifier/message.html.erb'), :layout => false)
        preview.gsub!(/\n/, "<br/>\n").gsub!(/http:\/\/[^\s<]+/, '<a href="\0">\0</a>')
        render(:update) do |page|
          page.replace_html 'preview-email', preview
          page.show 'preview'
        end
      else
        @message = Message.create(attributes)
        if @message.errors.any?
          add_errors_to_flash(@message)
          redirect_back
        else
          render :text => 'Your message has been sent.', :layout => true
        end
      end
    else
      render :text => "Sorry. We don't have an email address on file for #{@person.name}.", :layout => true, :status => :error
    end
  end
  
  def create_group_message(group_id)
    @group = Group.find(group_id)
    if @group.can_post? @logged_in
      @message = Message.create params[:message].merge(:person => @logged_in, :group => @group)
      if @message.errors.any?
        add_errors_to_flash(@message)
        redirect_back
      else
        render :text => 'Your message has been sent.', :layout => true
      end
    else
      render :text => 'You are not authorized to post to this group.', :layout => true, :status => :error
    end
  end
  
  public
  
  def destroy
    @message = Message.find(params[:id])
    if @logged_in.can_edit? @message
      @message.destroy
      redirect_back
    else
      render :text => 'Not authorized.', :status => 500
    end
  end
  
  # - - - - - - - - - - - - - - - - - - - - 
    
  def view
    @message = Message.find params[:id]
    unless @logged_in.sees? @message
      render :text => 'You are not allowed to view messages in this private group.'
    end
  end
  
  def edit
    if params[:id]
      @message = Message.find params[:id]
      unless @message.person == @logged_in
        raise 'You cannot edit a post you did not write.'
      end
    elsif flash[:message]
      @message = flash[:message]
    elsif params[:parent_id].to_i > 0
      parent = Message.find params[:parent_id]
      @message = Message.new :parent => parent, :group_id => parent.group_id, :person => @logged_in, :subject => "Re: #{parent.subject}", :dont_send => true
    elsif params[:group_id]
      @message = Message.new :group_id => params[:group_id], :person => @logged_in, :dont_send => true
    else
      raise 'Error.'
    end
    if @message.group and not @message.group.can_post? @logged_in
      render :text => 'You cannot post in this group.', :layout => true
      return
    end
    if request.post? and params[:message]
      if @message.update_attributes params[:message]
        flash[:notice] = 'Message saved.'
        if params[:file].size > 0
          attachment = @message.attachments.create(
            :name => File.split(params[:file].original_filename).last,
            :content_type => params[:file].content_type,
            :file => params[:file].read
          )
          if attachment.errors.any?
            flash[:notice] = attachment.errors.full_messages.join('; ')
          end
        end
        @message.send_to_group
        redirect_to @message.top
      else
        flash[:notice] = @message.errors.full_messages.join('; ')
      end
    else
      respond_to do |wants|
        wants.html { render :partial => 'edit_message', :layout => true }
        wants.js do
          render(:update) { |p| p.replace_html 'reply', :partial => 'edit_message' }
        end
      end
    end
  end
  
  def delete
    @message = Message.find params[:id]
    @message.destroy if @message.person == @logged_in or @message.wall == @logged_in or (@message.group and @message.group.admin? @logged_in) or @logged_in.admin?(:manage_messages)
    if @message.group
      redirect_to @message.group
    else
      redirect_to person_path(@message.wall_id), :anchor => 'wall'
    end
  end
  
  def send_email
    @person = Person.find params[:id]
    render :text => "Sorry. We don't have an email address on file for #{@person.name}.", :layout => true unless @person.email
    if request.post?
      if params[:subject].to_s.any? and params[:body].to_s.any?
        message = Message.create :person => @logged_in, :to => @person, :subject => params[:subject], :body => params[:body], :share_email => params[:share_email]
        if message.errors.any?
          flash[:notice] = message.errors.full_messages.join('; ')
        else
          render :text => 'Your message has been sent.', :layout => true
        end
      else
        flash[:notice] = 'You must enter a subject and a message.'
      end
    end
  end
  
  def preview_message
    params[:subject] = params[:message] ? params[:message][:subject] : params[:subject]
    params[:body] = params[:message] ? params[:message][:body] : params[:body]
    if params[:subject].to_s.any? or params[:body].to_s.any?
      if params[:id]
        @person = Person.find params[:id]
      else
        @group = Group.find params[:group_id]
      end
      @msg = Message.new :person => @logged_in, :subject => params[:subject], :body => params[:body], :share_email => false, :created_at => Time.now
      if @person
        @to = @msg.to = @person
        @msg.share_email = params[:share_email]
      else
        @msg.group = @group
        @to = Person.new
      end
      respond_to do |wants|
        wants.html { render :file => File.join(RAILS_ROOT, 'app/views/notifier/message.html.erb'), :layout => false }
        wants.js do
          preview = render_to_string :file => File.join(RAILS_ROOT, 'app/views/notifier/message.html.erb'), :layout => false
          preview.gsub!(/\n/, "<br/>\n").gsub!(/http:\/\/[^\s<]+/, '<a href="\0">\0</a>')
          render(:update) do |page|
            page.replace_html 'preview-email', preview
            page.show 'preview'
          end
        end
      end
    else
      render :nothing => true
    end
  end
  
  def view_attachment
    attachment = Attachment.find params[:id]
    unless attachment.message and attachment.message.group and @logged_in.sees? attachment.message.group
      render :text => 'You are not authorized to view this attachment.', :layout => true
      return
    end
    # TODO: routes this file serve through regular web server
    send_data File.read(attachment.file_path), :filename => attachment.name, :type => attachment.content_type, :disposition => 'inline'
  end
end
