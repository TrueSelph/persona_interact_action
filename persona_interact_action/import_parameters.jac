import logging;
import traceback;
import from logging { Logger }
import from jivas.agent.core.agent { Agent }
import from jivas.agent.action.action { Action }
import from jivas.agent.action.actions { Actions }
import from jivas.agent.modules.action.path { action_walker_path }
import from jivas.agent.action.agent_graph_walker { agent_graph_walker }


walker import_parameters(agent_graph_walker) {
    has data:list = "";
    has response:bool = False;
    has reporting:bool = True;

    static has logger:Logger = logging.getLogger(__name__);

    class __specs__ {
        static has private: bool = False;
        static has path: str = action_walker_path(__module__);
    }

    can on_agent with Agent entry {
        visit [-->](`?Actions);
    }

    can on_actions with Actions entry {
        visit [-->](`?Action)(?enabled==True)(?label=='PersonaInteractAction');
    }

    can on_action with Action entry {
        self.response = here.import_parameters(self.data);
        if self.reporting {
            report self.response;
        }
    }

}