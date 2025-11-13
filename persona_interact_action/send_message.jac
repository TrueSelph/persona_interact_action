import logging;
import asyncio;
import traceback;
import from logging { Logger }
import from jivas.agent.core.agent { Agent }
import from jivas.agent.action.action { Action }
import from jivas.agent.action.actions { Actions }
import from jivas.agent.action.agent_graph_walker { agent_graph_walker }
import from jivas.agent.memory.frame { Frame }
import from jivas.agent.action.interact { interact }
import from jivas.agent.memory.interaction { Interaction }
import from jivas.agent.memory.interaction_response { InteractionResponse, InteractionMessage, TextInteractionMessage, SilentInteractionMessage }

async walker send_message(agent_graph_walker) {
    # action endpoint for sending a message

    has visitor:agent_graph_walker = None;
    has agent_id:str = "";
    has session_id:str = "";
    has content:str = "";
    has response:list[dict] = [];
    has verbose: bool = False; # verbose payload or not
    has tts: bool = False; # activate text-to-speech response
    has streaming: bool = False; # activate streaming response
    has reporting: bool = True;
    has frame_node: Frame = None;
    has interaction_node: Interaction = None;
    has whatsapp_action: str = "WPPConnectAction";

    has response: dict = {};
    has message: InteractionMessage = None;


    can on_exit with exit{
        self.channel = self.interaction_node.channel;
        self.interaction_node = self.frame_node.create_interaction(utterance = self.content, channel = self.channel);

        # TODO add code to add the message to the current interaction_node

        self.interaction_node.set_message(
            TextInteractionMessage(content=self.content)
        );

        text_message = TextInteractionMessage(content=self.content);
        agent_node = &self.agent_id;
        if(whatsapp_action_node := agent_node.get_actions().get(action_label=self.whatsapp_action)) and self.channel=="whatsapp" {
            whatsapp_action_node.send_message(session_id=self.session_id, message=text_message);
        }
        # self.respond();
    }

    def respond() {
        # prepares and returns the response from the interaction node
        agent_node = &self.agent_id;

        if (agent_node and self.interaction_node) {

            interaction_data = {};
            # close the interaction
            self.interaction_node.close();
            # add the interaction to the frame
            self.frame_node.insert_interaction(self.interaction_node);

            # lets return the generated response, if we have one...
            has_response = self.interaction_node.has_response();

            if (has_response) {
                try  {
                    # set the message obj
                    self.message = self.interaction_node.get_message();
                    # prepare the response payload
                    interaction_data = self.interaction_node.export();

                    # handle verbose mode
                    if (self.verbose) {
                        interaction_data['frame'] = self.frame_node.export();
                        self.response = interaction_data;
                    } else {
                        self.response = {"response": self.interaction_node.get_response().export()};
                    }

                } except Exception as e {
                    self.logger.error(
                        f"an exception occurred, {traceback.format_exc()}"
                    );
                }
            }

            if (not has_response or not self.response) {
                self.message = SilentInteractionMessage();
                self.response = InteractionResponse(
                    session_id=self.frame_node.session_id,
                    message=self.message
                ).export();
            }

            # activate pruning protocol to shed old interactions beyond frame_size limit from this interaction frame
            self.frame_node.prune_interactions(
                frame_size=agent_node.frame_size
            );

        } else {
            self.message = SilentInteractionMessage();
            self.response = InteractionResponse(message=self.message).export();
        }

        # handle text-to-speech if enabled
        if (self.tts) {
            if (tts_action := agent_node.get_tts_action()) {
                # grab phoneme content if available
                content = self.message.data_get('phoneme_content')
                    or self.message.get_content();
                # perform TTS
                audio = tts_action.invoke(text=content, as_url=True);
                if (audio) {
                    self.response["response"].update({"audio_url": audio});
                }
            }
        }

        if (self.reporting) {
            report self.response;
        }
    }
}