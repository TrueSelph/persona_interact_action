import from jivas.agent.core.graph_node { GraphNode }
import from jivas.agent.modules.system.common { node_obj }


node ParameterEntry(GraphNode) {
    has condition:str = "";
    has response:str = "";
    has action:str = "";
    has enabled:bool = True;
    has metadata:dict = {};
    has collection_id:str = "";

    def get_parameter_entry() {
        return node_obj([<--]);
    }
}