import yaml;
import json;
import from jivas.agent.core.graph_node { GraphNode }
import from jivas.agent.modules.system.common { node_obj }
import from jac_cloud.plugin.jaseci { JacPlugin as Jac }
import from actions.jivas.persona_interact_action.parameter_entry { ParameterEntry }
import from actions.jivas.persona_interact_action.parameter { Parameter }

node Parameters(GraphNode) {
    has collection_id:str = "";

    def create_parameter_entry(parameter_data:dict) -> ParameterEntry {

        parameter = Parameter(
            collection_id = self.collection_id,
            condition = parameter_data.get("condition", ""),
            response = parameter_data.get("response", ""),
            action = parameter_data.get("action", ""),
            enabled = True,
            metadata = parameter_data.get("metadata", {})
        );
        # now we attach it to the node
        self ++> parameter;

        return parameter;
    }

    def get_parameter_entry(id:str) -> ParameterEntry {
        # retrieves an attached parameter entry by id
        return node_obj([-->](`?ParameterEntry)(?id == id));
    }

    def get_parameter_entries() -> list {
        # retrieves a list of parameter entries
        return [-->](`?ParameterEntry);
    }

    def update_parameter_entry(id:str, data:dict) -> Union[dict, None] {
        try {
            if(parameter := node_obj([-->](`?ParameterEntry)(?id == id))){
                parameter.update(data);
                return parameter;
            }
        } except Exception as e {
            return None;
        }
        return None;
    }

    def get_parameter_entry_by_condition(condition:str) -> ParameterEntry{
        # retrieves an attached parameter entry by id
        return node_obj([-->](`?ParameterEntry)(?condition == condition));
    }

    def delete_parameter_entry(id:str) -> bool {
        # removes an attached document entry by id
        parameter_entry = node_obj([-->](`?ParameterEntry)(?id == id));
        if not parameter_entry {
            return False;
        }
        Jac.destroy( parameter_entry );
        # if this is the last entry in this job, also remove the job itself
        if not [-->](`?ParameterEntry) {
            self.delete();
        }
        return True;
    }

    def delete() -> list {
        return (self spawn _purge_job()).removed;
    }

}

walker _purge_job {
    # walker which carries out the traversal and purging of jobs and any related docs

    has removed:list = [];

    obj __specs__ {
        # make this a private walker
        static has private: bool = True;
    }

    can on_job with Parameters entry {
        visit [-->];
        self.removed.append(here);
        Jac.destroy(here);
    }

    can on_parameter_entry with ParameterEntry entry {
        self.removed.append(here);
        Jac.destroy(here);
    }
}