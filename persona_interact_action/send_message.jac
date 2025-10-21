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

    set up logger
    static has logger:Logger = logging.getLogger(__name__);

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
    }
}