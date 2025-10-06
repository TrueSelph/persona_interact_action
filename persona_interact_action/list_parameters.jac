import logging;
import from logging { Logger }
import from jivas.agent.core.agent { Agent }
import from jivas.agent.action.action { Action }
import from jivas.agent.action.actions { Actions }
import from jivas.agent.action.agent_graph_walker { agent_graph_walker }
import from jivas.agent.modules.action.path { action_walker_path }


walker list_parameters(agent_graph_walker) {
    # action endpoint for listing all documents processed by the deepdoc service

    has page:int = 1;
    has per_page:int = 10;
    has all:bool = False;  # new flag to indicate whether to return all documents
    has response:list[dict] = [];
    has reporting:bool = True;

    # set up logger
    static has logger:Logger = logging.getLogger(__name__);

    class __specs__ {
        static has private: bool = False;
        static has path: str = action_walker_path(__module__);
        static has excluded: list[str] = ["response"];  # exclude response from the specs
    }

    can on_agent with Agent entry {
        visit [-->](`?Actions);
    }

    can on_actions with Actions entry {
        visit [-->](`?Action)(?enabled==True)(?label=='PersonaInteractAction');
    }
    

    can on_action with Action entry {
        # get the list of documents from the manifest

        if self.all {
            self.response = here.list_parameters(page=self.page, limit=0);  # fetch all documents
        } else {
            self.response = here.list_parameters(page=self.page, limit=self.per_page);  # fetch paged documents
        }

        if self.reporting {
            report self.response;
        }
    }
}