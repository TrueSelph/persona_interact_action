import:py json;
import:py logging;
import:py traceback;
import:py from logging { Logger }
import:py from jivas.agent.modules.agentlib.utils { Utils }
import:jac from jivas.agent.action.interact_action { InteractAction }
import:jac from jivas.agent.memory.interaction_response { TextInteractionMessage }
import:jac from jivas.agent.action.interact_graph_walker { interact_graph_walker }


node PersonaInteractAction :InteractAction: {
    # driven by a modular prompt to provide role, history and context for LLM chat and/or retrieval augmented generation

    # set up logger
    static has logger:Logger = logging.getLogger(__name__);

    has timezone:str = "America/Guyana";
    has history:bool = True;
    has user_model:bool = True;
    has history_size:int = 3;
    has max_statement_length:int = 200;
    has model_action:str = "LangChainModelAction";
    has model_name:str = "gpt-4o";
    has model_temperature:float = 0.7;
    has model_max_tokens:int = 2048;
    has prompt:str = "Your name is Agent. Refer to the user as '{user}', if not None. Keep in mind '{date}' and '{time}' to be aware of the current date and time.  {directives}";
    has user_model_directive:str = "Employ the user information below as is relevant to inform your final response: \n\n{{user_model}}";
    has channel_format_directive:dict = {
        "whatsapp": "Please format your message using the following WhatsApp formats:\n- Italic: text\n- Bold: text\n- Strikethrough: text\n- Monospace: text\n- Bulleted list: * text or - text\n- Numbered list: 1. text\n- Quote: > text\n- Inline code: text\n- provide links as plain text (no clickable links)",
        "facebook": "Please format your message using the following Facebook formats:\n- Italic: _Text_\n- Bold: *Text*\n- Strikethrough: ~Text~\n- Monospace: `Text`\n- Codeblock: ```Text```"
    };

    can post_register() {
        # to ensure compatibility, this action is added to the exception list in intent_classifier

        if(intent_interact_action_node := self.get_agent().get_actions().get(action_label='IntentInteractAction')) {
            if(self.get_type() not in intent_interact_action_node.exceptions) {
                intent_interact_action_node.exceptions += [self.get_type()];
            }
        }

    }

    can touch(visitor: interact_graph_walker) -> bool {
        # authorize, redirect or deny the interact walker here
        # only executes if response message is empty
        if (visitor.utterance and not visitor.interaction_node.has_response()) {
            return True;
        }

        return False;
    }

    can execute(visitor: interact_graph_walker) -> dict {

        # format response by channel
        self.handle_channel_format(visitor=visitor);

        # grab user's name, if set
        user = visitor.frame_node.get_user_name();

        date = Utils.date_now(timezone=self.timezone, date_format='%A, %d %B, %Y');
        time = Utils.date_now(timezone=self.timezone, date_format='%I:%M %p');

        if (self.user_model) {
            user_model_content = visitor.frame_node.variable_get(key="user_model");
            if (user_model_content) {
                user_model_prompt = Utils.replace_placeholders(self.user_model_directive, {'user_model': user_model_content});
                if (user_model_prompt) {
                    visitor.interaction_node.add_directive(directive=user_model_prompt);
                }
            }
        }

        # prepare directives
        directives = self.prepare_persona_task_directives( visitor.interaction_node.get_directives() );

        # prepare the final prompt with history.
        if (self.history) {
            # grab the history
            prompt_messages = [];

            statements = visitor.frame_node.get_transcript_statements(interactions = self.history_size, max_statement_length = self.max_statement_length, with_events = True);

            if (statements) {
                prompt_messages.extend(statements);
                self.logger.debug(f"history: {json.dumps(statements)}");
            }

            prompt_messages.extend([{"system": self.prompt}]);
        } else {
            # here we cater to whether we have context information or not..
            prompt_messages = [
                {"system": prompt},
                {"human": "{utterance}"}
            ];
        }

        if(model_action := self.get_agent().get_actions().get(action_label=self.model_action)) {

            if( model_action_result := model_action.call_model(
                prompt_messages = prompt_messages,
                prompt_variables = {
                    "user": user,
                    "date": date,
                    "time": time,
                    "directives": directives,
                    "utterance": visitor.utterance
                },
                kwargs = {
                    "model_name": self.model_name,
                    "model_temperature": self.model_temperature,
                    "model_max_tokens": self.model_max_tokens
                },
                interaction_node = visitor.interaction_node
            )) {

                # set the interaction message+
                interaction_message = model_action_result.get_result();
                if not interaction_message {
                    interaction_message = "...";
                }

                visitor.interaction_node.set_message( TextInteractionMessage(content = interaction_message) );
            }

        }

        return visitor.export();
    }

    can prepare_persona_task_directives(directives:list) -> str{
        directives_str = "";
        index = 1;

        for directive in directives {
            directives_str = directives_str + (str(index) + ". " + directive + "\n");
            index = index + 1;
        }

        if(directives_str) {
            directives_str = "### RESPONSE DIRECTIVES \n Generate your response by executing the directives below carefully and in order: \n" + directives_str;
        }

        return directives_str;
    }

    can handle_channel_format(visitor: interact_graph_walker) -> dict {
        channel = visitor.interaction_node.channel;

        if(channel in self.channel_format_directive) {
            visitor.interaction_node.add_directive(directive=self.channel_format_directive[channel]);
        }
    }

    can healthcheck() -> bool {
        try {
            if(
                self.timezone and
                self.max_statement_length > 0 and
                self.model_action and
                self.model_name and
                self.model_max_tokens > 0 and
                self.prompt and
                self.user_model_directive and
                self.channel_format_directive
            ){
                return True;
            }
            return False;
        } except Exception as e {
            self.logger.error(f"An exception occurred in {self.label}:\n{traceback.format_exc()}\n");
            return False;
        }
    }
}
