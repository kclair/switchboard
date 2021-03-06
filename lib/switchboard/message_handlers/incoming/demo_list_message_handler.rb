require 'switchboard/message_handlers/incoming_message_handler.rb'
require 'twilio/twilio_sender'

module Switchboard::MessageHandlers::Incoming
  class DemoListMessageHandler < Switchboard::MessageHandlers::IncomingMessageHandler
    def handle_messages!()
      ## should be  outgoing_states.each |state,conditions| do 
      handled_state = MessageState.find_by_name('handled')
      messages_to_handle.each do |message|
        tokens = message.body.split(/ /)
        puts tokens.to_s 

        puts "Message was sent to: " + message.to

        message_sender = ''
        if ( List.find_by_incoming_number(message.to) != nil)
          puts "found list w/out keyword!"
          list_name = List.find_by_incoming_number(message.to).name
          message_sender = message.to
        elsif ( message.respond_to? :carrier )
          list_name = message.default_list 
          puts "received email message for list " + list_name
          message_sender = message.to
        elsif ( message.from_web? )
          puts "received web message"
          list_id = message.to
          list_name = List.find_by_id(list_id).name
          puts " -- web message for list " + list_name
          message_sender = '2153466997'
        else
          list_name = tokens.shift
          list_name.upcase!
          puts "received text message for list: " + list_name
          message_sender = '2153466997'
        end


        if (message.respond_to? :carrier ) 
          number_string = message.number
        else
          number_string = message.from
        end  

        puts "Message is from number: " + number_string

        num = PhoneNumber.find_or_create_by_number( number_string ) 
        num.save

        if (message.respond_to? :carrier)  
          num.provider_email = message.carrier 
        end  

        if ( list_name =~ /^leave$/i or list_name =~ /^quit$/ )
          create_outgoing_message( num, message.to, "I think you have asked to not recieve any more text messages, so I am dropping you from all of our lists." )
          lists = List.find(:all).each { |l|
            l.remove_phone_number(num)
          } 
          handled_state.messages.push(message)
          next;
        end 

        puts "processing message" 
        if (tokens.length == 0 or ( tokens.length == 1 and tokens[0] =~ /join/i ) )  ## join message
          puts "join message found"

          list = List.find_by_name(list_name)
          if (list == nil) 
            create_outgoing_message( num, message.to, "I'm sorry, but I'm not sure what you're trying to do." )
            handled_state.messages.push(message)
            next
          end

          if list.has_number?(num) 
            create_outgoing_message( num, message.to, "It seems like you are trying to join the list '" + list_name + "', but you are already a member.")
          else
            if (list.open_membership)
              message.list = list
              if (num.user == nil)
                puts "adding user for num: " + num.number
                num.user = User.create(:password => 'abcdef981', :password_confirmation => 'abcdef981')
                num.save
                num.user.save
              end

              list.add_phone_number(num)

              message.sender = num.user
              message.save
              #welcome_message = "You have joined the text message list called '" + list_name + "'!"
              #if list.use_welcome_message?:
              #  puts "this list uses the welcome message"
              #  welcome_message = list.custom_welcome_message
              #end

              #create_outgoing_message( num, message.to, welcome_message ) 
            else ## not list.open_membership
              create_outgoing_message( num, message.to, "I'm sorry, but this list is configured as a private list and only the administrator can add new members.")
            end
          end
          handled_state.messages.push(message)
          next 
        elsif ( tokens.length == 1 and ( tokens[0] =~ /^leave$/i or tokens[0] =~ /^quit$/i )  )   ## join message
          puts "Quitting list.  Message was: " + tokens[0]
          list = List.find_by_name(list_name)
          create_outgoing_message( num, message.to, "I think you have asked to leave this list, so I am dropping you from the " + list_name + " list." )
          list.remove_phone_number(num)
          list.save
          handled_state.messages.push(message)
          next
       else ## not a join message
            if List.exists?({:name => list_name}) 
              puts "List received a message"
              list = List.find_by_name(list_name)
              message.list = list
              message.sender = num.user 
              message.save
              if (message.from_web? or list.all_users_can_send_messages? or list.admin == num)
                list.phone_numbers.each do |phone_number|
                  body = '[' + list_name + '] ' + tokens.join(' ')
                  puts "sending message: " + body + ", to: " + phone_number.number
                  list.create_outgoing_message(phone_number, body)
                end
              else
                if (list.admin != nil)
                  admin_msg = '[' + list_name + ' from '
                    admin_msg +=  num.number.to_s

                  if ( num.user != nil and (! num.user.first_name.blank?) )
                    admin_msg += "/ " + num.user.first_name.to_s + " " + num.user.last_name.to_s 
                  end

                  admin_msg += '] '
                  admin_msg += tokens.join(' ') 
                  create_outgoing_message( list.admin, message_sender, admin_msg )
                end
              end
              handled_state.messages.push(message)
            else 
              create_outgoing_message(num, message_sender, "I'm sorry but I'm not sure what list you're trying to reach!" ) unless message.from_web?
              handled_state.messages.push(message)
            end
        end
      handled_state.save
    end  ## message loop -- handled a message
  end

      def create_outgoing_message(num, from, body)
          if ( num.provider_email != '' and num.provider_email != nil  )
            puts "sending email message"
            message = EmailMessage.new
            message.to = num.number + "@" + num.provider_email
            message.from = from
          else
            puts "sending twilio message to: " + num.number
            message = TwilioMessage.new
            message.to = num.number
          end

          message.body = body

          message_state = MessageState.find_by_name("outgoing")
          message_state.messages.push(message)
          message_state.save! 
      end
    end
end
