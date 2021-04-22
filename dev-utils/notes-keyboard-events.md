core.step
    call `system.poll_event`
    
        Two kind of events related to keyboard input: "textinput" and
        "keypressed/released. The event "textediting" is ignored in the lite
        application because it is for incomplete text composition.
        
        If the event is "textinput" and the previous keyboard event was treated
        by keymap (within the `core.on_event` function) the event is not
        treated. In all other cases ("textinput" or "keypressed/released") the
        event is passed to `core.on_event`.
        
        The logic above seems to be there to prevent treating a "textinput" if a
        previous keyboard event was previously treated and recognized as a
        command.
    
        call `core.on_event`
        
            if type == "textinput":

            call `core.root_view:on_text_input`
            
            and in turn:
            
            call `core.active_view:on_text_input`
                passed down to the corresponding method of the view
            
            if type == "keypressed":

            call `keymap.on_key_pressed`
                recognize and execute the commands stored in the "keymap"
    
