import from jivas.agent.core.agent { Agent }
import from jivas.agent.action.action { Action }
import from jivas.agent.action.actions { Actions }
import from jivas.agent.modules.action.path { action_walker_path }
import from jivas.agent.action.agent_graph_walker { agent_graph_walker }


walker delete_collection(agent_graph_walker) {

    has response:bool = False;
    has reporting:bool = True;

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
        self.response = here.delete_collection();

        if self.reporting {
            report self.response;
        }
    }

}