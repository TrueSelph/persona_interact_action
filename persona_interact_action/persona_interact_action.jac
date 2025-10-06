import json;
import yaml;
import os;
import logging;
import traceback;
import from logging { Logger }

import from jivas.agent.modules.system.common { date_now }

import from jivas.agent.action.interact_action { InteractAction }
import from jivas.agent.memory.interaction_response { TextInteractionMessage, SilentInteractionMessage }
import from jivas.agent.action.agent_graph_walker { agent_graph_walker }
import from jivas.agent.modules.data.node_get { node_get }
import from jivas.agent.modules.system.common { node_obj }
import from jivas.agent.memory.collection { Collection }
import from jac_cloud.core.archetype {BaseCollection, NodeAnchor}
import from jivas.agent.modules.data.node_pager { NodePager }
import from actions.jivas.persona_orchestrator_interact_action.parameters { Parameters }
import from actions.jivas.persona_orchestrator_interact_action.parameter_entry { ParameterEntry }
import from actions.jivas.persona_orchestrator_interact_action.parameter { Parameter }
import from jivas.agent.memory.frame { Frame }


node PersonaInteractAction(InteractAction) {
    # driven by a modular prompt to provide role, history and context for LLM chat and/or retrieval augmented generation

    # set up logger
    static has logger:Logger = logging.getLogger(__name__);

    has timezone:str = "America/Guyana";
    has history:bool = True;
    has history_size:int = 3;
    has max_statement_length:int = 500;
    has model_action:str = "LangChainModelAction";
    has model_name:str = "gpt-4o";
    has model_temperature:float = 0.3;
    has model_max_tokens:int = 4096;
    has parameter_filename:str = "parameters.yaml";
    has parameters:list = [];

    #agent details
    has agent_name:str = "Agent";
    has agent_role:str = "An AI Assistant";
    has agent_description:str = "friendly and helpful";
    has prompt:str = "";
    has agent_prompt_template:str = """
Your name is {agent_name}. Your role is {agent_role}. 
You are {agent_description}. 
Refer to the user as '{user}', if not None. Keep in mind '{date}' and '{time}' to be aware of the current date and time. 
TASK DESCRIPTION:
-----------------
Continue the provided interaction in a natural and human-like manner.
Your task is to produce a response to the latest state of the interaction.
Always abide by the following general principles (note these are not the "parameters". The parameters will be provided later):
1. GENERAL BEHAVIOR: Make your response as human-like as possible. Be concise and avoid being overly polite when not necessary.
2. AVOID REPEATING YOURSELF: When replying— avoid repeating yourself. Instead, refer the user to your previous answer, or choose a new approach altogether. If a conversation is looping, point that out to the user instead of maintaining the loop.
3. REITERATE INFORMATION FROM PREVIOUS MESSAGES IF NECESSARY: If you previously suggested a solution or shared information during the interaction, you may repeat it when relevant. Your earlier response may have been based on information that is no longer available to you, so it's important to trust that it was informed by the context at the time.
4. MAINTAIN GENERATION SECRECY: Never reveal details about the process you followed to produce your response. Do not explicitly mention the tools, context variables, parameters, glossary, or any other internal information. Present your replies as though all relevant knowledge is inherent to you, not derived from external instructions.
5. RESOLUTION-AWARE MESSAGE ENDING: Do not ask the user if there is “anything else” you can help with until their current request or problem is fully resolved. Treat a request as resolved only if a) the user explicitly confirms it; b) the original question has been answered in full; or c) all stated requirements are met. If resolution is unclear, continue engaging on the current topic instead of prompting for new topics.
6. EASY-TO-READ FORMATTING:  MAKE RESPONSES EASY TO READ WAY BY UTILIZING PARAGRAPHS AND MARKDOWN WHEN NECESSARY

{parameters}

{directives} 
        """;

    has no_parameters_instruction:str = """
### PARAMETERS
In formulating your reply, you are normally required to follow a number of behavioral parameters.
However, in this case, no special behavioral parameters were provided. Therefore, when generating revisions,
you don't need to specifically double-check if you followed or broke any parameters.
Instead adhere to any directives given
""";
    has directives_instrtuction:str = """
### DIRECTIVES
Directives are instructions that you should follow when responding to the user
Avoid mentioning or asking for things not specified by the directive
Be as concise as possible when carrying out the directive
You must follow the directive unless the directive conflicts with a parameter. 
Parameters take priority over directives so if there is a conflict, obey the parameter.
Generate your response by executing the directives below carefully and in order: 
""";
    has no_directives_instruction:str = """
### DIRECTIVES
There are no specific directives for this interaction. 
Please generate your response using your best judgment, following general conversational principles and the agent’s behavioral parameters. 
Focus on being clear, concise, and helpful in addressing the user’s request.
    """;
    has parameter_directive:str = "### PARAMETERS \nWhen crafting your reply, you must follow the behavioral parameters provided below, which have been identified as relevant to the current state of the interaction.";
    has parameters_instruction:str = """
You may choose not to follow a parameter only in the following cases:
    - It conflicts with a previous customer request.
    - It is clearly inappropriate given the current context of the conversation.
    - It lacks sufficient context or data to apply reliably.
    - It conflicts with an insight.
    - It depends on an agent intention condition that does not apply in the current situation (as mentioned above)
    - If a parameter offers multiple options (e.g., "do X or Y") and another more specific parameter restricts one of those options 
        (e.g., "don’t do X"), follow both by choosing the permitted alternative (i.e., do Y).
In all other situations, you are expected to adhere to the parameters.
These parameters have already been pre-filtered based on the interaction's context and other considerations outside your scope.
    """;
    has channel_format_directives: dict = {
        "facebook": (
            "Structure Facebook content with these formatting rules:\n"
            "- Italic: Wrap text with underscores (_text_)\n"
            "- Bold: Wrap text with asterisks (*text*)\n"
            "- Strikethrough: Wrap text with tildes (~text~)\n"
            "- URLs: Reformat all URLs to use raw URLs and not hyperlinks.\n"
            "- Separate paragraphs with line breaks"
        ),

        "whatsapp": (
            "Structure WhatsApp messages with these rules:\n"
            "- Italic: Surround with underscores (_text_)\n"
            "- Bold: Surround with asterisks (*text*)\n"
            "- Strikethrough: Surround with tildes (~text~)\n"
            "- Bullet lists: Start lines with * or -\n"
            "- Numbered lists: Begin with 1. 2. 3.\n"
            "- Quotes: Prefix lines with > symbol\n"
            "- URLs: Reformat all URLs to use raw URLs and not hyperlinks.\n"
            "- Separate sections with line breaks"
        ),

        "instagram": (
            "Structure Instagram content with:\n"
            "- Bold: Surround text with asterisks (*text*)\n"
            "- Italic: Surround text with underscores (_text_)\n"
            "- URLs: Reformat all URLs to use raw URLs and not hyperlinks.\n"
            "- Use single line breaks between paragraphs\n"
            "- Maximum 30 hashtags at caption end"
        ),

        "twitter": (
            "Structure Twitter/X posts with:\n"
            "- Bold: Use asterisks (*text*)\n"
            "- Italic: Use underscores (_text_)\n"
            "- URLs: Reformat all URLs to use raw URLs and not hyperlinks.\n"
            "- Threads: Start with (1/3) indicator\n"
            "- Keep under 280 characters per tweet"
        ),

        "linkedin": (
            "Structure LinkedIn posts with:\n"
            "- Bold: Asterisks around text (*text*)\n"
            "- Italic: Underscores around text (_text_)\n"
            "- Bullets: Start lines with * or -\n"
            "- URLs: Reformat all URLs to use raw URLs and not hyperlinks.\n"
            "- Sections: Separate with --- on own line\n"
            "- Paragraphs: Maximum 5 lines each"
        ),

        "email": (
            "Structure emails with:\n"
            "- Bold: Surround with asterisks (*important*)\n"
            "- Italic: Surround with underscores (_emphasis_)\n"
            "- Lists: Use * or - for bullet points\n"
            "- Quotes: Begin lines with > symbol\n"
            "- URLs: Reformat all URLs to use raw URLs and not hyperlinks.\n"
            "- Subject lines: Under 60 characters\n"
            "- Include formal greetings/closings"
        ),

        "sms": (
            "Structure SMS messages with:\n"
            "- No special formatting symbols\n"
            "- URLs: Reformat all URLs to use raw URLs and not hyperlinks.\n"
            "- Length: Maximum 160 characters\n"
            "- Line breaks: Use basic separation\n"
            "- Avoid emojis unless requested"
        )
    };

    def on_register() {
        # import parameters 
        self.import_parameters(self.parameters);
    }


    def touch(visitor:agent_graph_walker) -> bool {
        # authorize, redirect or deny the interact walker here
        # only executes if response message is empty
        return (visitor.utterance and not visitor.interaction_node.has_response());
    }


    #  Executes the main persona interaction action.
    #  Handles prompt construction, parameter filtering, action execution, and model invocation.

    def execute(visitor:agent_graph_walker) -> None {

        # format response by channel
        self.handle_channel_format(visitor=visitor);

        # grab user's name, if set
        user = visitor.frame_node.get_user_name();

        date = date_now(timezone=self.timezone, date_format='%A, %d %B, %Y');
        time = date_now(timezone=self.timezone, date_format='%I:%M %p');

        # prepare the prompt with utterance
        prompt_messages = [];

        # add history to prompt if configured.
        if (self.history) {
            statements = visitor.frame_node.get_transcript_statements(
                interactions = self.history_size,
                max_statement_length = self.max_statement_length,
                with_events = True
            );
            if (statements) {
                prompt_messages = statements;
            }
        }
        # add human message
        prompt_messages.append({"human": visitor.utterance});

        # process parameters
        parameters_list = self.get_parameter_entries();
        parameters = [];
        if parameters_list{
            for param in parameters_list{
                if param.enabled{
                    parameters.append(param);
                }
            }
        }
        filtered_parameters_list = self.filter_parameters(prompt_messages, parameters);
        action_responses = self.run_actions(filtered_parameters_list, visitor);

        for action_response in action_responses{
            visitor.interaction_node.add_directive(directive = action_response);
        }

        # add any active events in this interaction
        if events := visitor.frame_node.get_active_event_statements() {
            prompt_messages.extend(events);
        }
        directives_list = visitor.interaction_node.get_directives();

        # formulate a complete prompt and add the system prompt last
        final_prompt = self.create_agent_prompt(filtered_parameters_list, directives_list);
        prompt_messages.append({"system": final_prompt});

        model_action := self.get_agent().get_action(action_label=self.model_action);
        if not model_action {
            self.logger.error(f"Model action not found for label: {str(self.model_action)}");
            return;
        }

        model_action_result = model_action.call_model(
            prompt_messages=prompt_messages,
            prompt_variables={
                "user": user,
                "date": date,
                "time": time
            },
            streaming=visitor.streaming,
            interaction_node=visitor.interaction_node,
            model_name=self.model_name,
            model_temperature=self.model_temperature,
            model_max_tokens=self.model_max_tokens
        );

        if not model_action_result {
            self.logger.error("Model action result is None.");
            # return;
        }

        # set the interaction message
        interaction_message = model_action_result.get_result() or "...";

        visitor.interaction_node.set_message(
            TextInteractionMessage(content=interaction_message)
        );
    }

    def model_call(prompt_messages:list, prompt_variables:dict) -> any {
        try {
            model_action := self.get_agent().get_action(action_label=self.model_action);
            if not model_action {
                self.logger.error("Model action not found for label: " + str(self.model_action));
                return None;
            }

            model_action_result = model_action.call_model(
                prompt_messages=prompt_messages,
                prompt_variables=prompt_variables,
                model_name=self.model_name,
                model_temperature=self.model_temperature,
                model_max_tokens=self.model_max_tokens
            );

            if not model_action_result {
                self.logger.error("Model action result is None.");
                return None;
            }

            message = model_action_result.get_result() or "...";
            if not message{
                message = model_action_result.get_json_result() or {};
            }
            return message;
        } except Exception as e {
            self.logger.error(f"Exception in model_call: {traceback.format_exc()}");
            return None;
        }
    }

    def get_parameter_entries() -> list {
        # Retrieves all the parameters from the collection.

        collection = self.get_collection();
        parameter_node = Parameters(collection_id=collection.id);
        try{
            parameters = node_obj(node_get({
                "name": "Parameters",
                "archetype.collection_id": collection.id,
            }));

            parameter_list = parameters.get_parameter_entries();
            if parameter_list{
                return parameter_list;
            }else{
                return [];
            }
        }except Exception as e{
            return [];
        }
    }

    def prepare_persona_task_directives(directives:list) -> str {
        directives_str = "";
        index = 1;

        for directive in directives {
            directives_str = directives_str + (str(index) + ". " + directive + "\n");
            index = index + 1;
        }

        if(directives_str) {
            directives_prompt = self.directives_instrtuction + directives_str;
        }
        else{
            directives_prompt = self.no_directives_instruction;
        }

        return directives_prompt;
    }

    def run_actions(parameters_list:list, visitor:agent_graph_walker) -> list {
        # run other actions depending on parameters

        action_responses = [];
        visitor.frame_node.data_set(key="visitor_utterance", value=visitor.utterance);

        for parameter in parameters_list{

            if parameter.action and ('Interact' not in parameter.action){
                action_node = self.get_agent().get_action(action_label=parameter.action);
                action_response = action_node.run(frame_node=visitor.frame_node);
                if type(action_response) is str{
                    action_responses.append(action_response);
                }
                elif type(action_response) is list{
                    for response in action_response{
                        action_responses.append(response);
                    }
                }
            }
            elif parameter.action and ('Interact' in parameter.action){
                action_node = self.get_agent().get_actions().get(action_label=parameter.action);
                action_node.touch(visitor);
            }
        }
        return action_responses;
    }

    def get_parameters_prompt(parameters_list:list) -> str {
        # add parameters to the prompt to guide the model's behavior
        index = 1;
        parameters_str = "";
        parameter_prompt_list =  [];
        parameters_prompt = " ";


        if parameters_list{
            for parameter in parameters_list{
                if(parameter.condition and parameter.response){
                    parameter_prompt_list.append(f"When {parameter.condition}, then {parameter.response}");
                }
            }
        
            if(parameter_prompt_list) {
                for parameter in parameter_prompt_list {
                    parameters_str = parameters_str + (str(index) + ". " + parameter + "\n");
                    index+=1;
                }
                parameters_prompt = self.parameter_directive + "\n" + parameters_str + "\n" + self.parameters_instruction;
            }
            else{
                parameters_prompt = self.no_parameters_instruction;
            }
        }
        else{
            parameters_prompt = self.no_parameters_instruction;
        }
        return parameters_prompt;
    }

    def create_agent_prompt(parameters_list:list, directives_list:list) -> str {
        # create the final prompt to send to the model
        parameters_prompt = self.get_parameters_prompt(parameters_list);
        directives_prompt = self.prepare_persona_task_directives(directives_list);

        final_prompt = self.agent_prompt_template.replace("{parameters}", parameters_prompt);
        final_prompt = final_prompt.replace("{directives}", directives_prompt);
        final_prompt = final_prompt.replace("{agent_name}", self.agent_name);
        final_prompt = final_prompt.replace("{agent_description}", self.agent_description);
        final_prompt = final_prompt.replace("{agent_role}", self.agent_role);

        if self.prompt{
            final_prompt = final_prompt + "### ADDITIONAL DETAILS\n" + self.prompt;
        }
        return final_prompt;
    }

    def filter_parameters(messages_for_llm:list, parameters_list:list) -> list {
        filter_parameter_prompt = """

        TASK DESCRIPTION
        -----------------
        You are tasked with evaluating a list of parameters against the context of a conversation. Your goal is to identify which parameters are applicable based on the user's last message.

        Parameters: Each parameter  is an python object that consists of a condition and a response. The condition specifies when the parameter should apply.
        Conversation History: Review the last few messages to understand the context.
        Instructions:

        Analyze the user's last message.
        Compare it with each parameter's condition.
        Return a list of parameters where the condition matches the context of the last message.
        Example:

        If the user's last message is "What's the weather like?", and a parameter condition is "the user asks about the weather", then this parameter is applicable.
        However, if the user's last message is "What's the weather like?", and a parameter condition is "the user greets the agent", then this parameter is not applicable
        return only a list of applicable parameters Ids. Do not give any explanations or reasoning for picking the parameter.

        GUIDELINES:
        {parameters}
        """;

        if parameters_list{
            prompt_messages = messages_for_llm.copy();
            prompt_messages.append({"system": filter_parameter_prompt});
            prompt_variables ={
                "parameters":parameters_list
            };

            applicable_parameters = [];
            applicable_parameters_ids = self.model_call(prompt_messages, prompt_variables);

            if applicable_parameters_ids{
                for parameter in parameters_list{
                    if parameter.id in applicable_parameters_ids {
                        applicable_parameters.append(parameter);
                    }
                }
            }
            return applicable_parameters;
        }else{
            return [];
        }
    }

    def handle_channel_format(visitor: agent_graph_walker) -> dict {
        channel = visitor.interaction_node.channel;

        if(channel in self.channel_format_directives) {
            visitor.interaction_node.add_directive(directive=self.channel_format_directives[channel]);
        }
    }

    def healthcheck() -> bool {
        try {
            if(
                self.prompt and
                (model_action := self.get_agent().get_actions().get(action_label=self.model_action))
            ){
                return True;
            }
            return False;
        } except Exception as e {
            self.logger.error(f"An exception occurred in {self.label}:\n{traceback.format_exc()}\n");
            return False;
        }
    }

    #  * Loads parameters from a provided list and imports them into the graph.
    #  * Ensures file closure and validates YAML structure.
    def import_parameters(parameters:list=[]) -> None {
        try {
            if not parameters{
                # gets parameters from file in persona directory
                current_directory = os.path.dirname(os.path.abspath(__file__));
                filepath = current_directory + "/" + self.parameter_filename;
                yaml_file = None;
                try {
                    yaml_file = open(filepath, 'r');
                    yaml_content = yaml.safe_load(yaml_file);
                    if not isinstance(yaml_content, list) {
                        self.logger.error("YAML content is not a list of parameters.");
                        return None;
                    }
                    parameters = yaml_content;
                } finally {
                    if yaml_file {
                        yaml_file.close();
                    }
                }
            }

            # purging collection and import new parameters
            collection = self.get_collection();
            if not collection {
                self.logger.error("Collection not found in import_parameters.");
                return None;
            }
            parameter_node = Parameters(collection_id=collection.id);
            import_collection = collection spawn _import_collection(document=parameters);

        } except Exception as e {
            self.logger.error(f"Document loading failed: {traceback.format_exc()}");
            return None;
        }
    }

    def list_parameters(page:int, limit:int) -> list[dict]{
        collection = self.get_collection();
        # Initialize pager
        pager = NodePager(NodeAnchor.Collection, page_size=limit, current_page=page);

        # Get a page of results
        items = pager.get_page({
            "$and": [{"name": "Parameter"}, {"archetype.collection_id": collection.id}],
            
        });

        if not items {
            return {};
        }

        # call export on each and convert it to a dict
        items = [item.export() for item in items];

        # get all info as a dict
        pagination_info = pager.to_dict();

        return {
            "page": page,
            "limit": limit,
            "items": items
        };
    }

    def get_parameters_node() -> Optional[Parameters] {
        # Retrieves a job entry by job_id from the collection.
        collection = self.get_collection();

        parameters_node = node_obj(node_get({
            "name": "Parameters",
            "archetype.collection_id": collection.id
        }));

        return parameters_node;
    }

    def update_parameter(id:str, data:dict) -> Union[dict, None] {

        parameter_node = self.get_parameters_node();

        if not parameter_node {
            self.logger.error(f"Parameter not found in collection.");
            return {};
        }else {

            new_param = parameter_node.update_parameter_entry(id=id, data=data);

            if not new_param {
                self.logger.error(f"Parameter entry with ID '{id}' not found.");
                return {};
            }
        }

        return None;
    }

    def delete_collection() -> bool {
        try {
            if collection := self.get_collection {
                result = self.get_agent().get_memory().purge_collection_memory(self.label);
                return result;
            }
        } except Exception as e {
            self.logger.error(f"Collection deletion failed: {traceback.format_exc()}");
        }
        return False;
    }
}

walker _import_collection {
    has document:list = [];

    obj __specs__ {
        static has private:bool = True;
    }

    can on_collection with Collection entry {
        visit [-->](`?Parameters) else {
            parameters = Parameters(collection_id=here.id);
            here ++> parameters;

            for document_entry in self.document {

                parameter = Parameter(
                    collection_id = here.id,
                    condition = document_entry.get("condition", ""),
                    response = document_entry.get("response", ""),
                    action = document_entry.get("action", ""),
                    enabled = True,
                    metadata = document_entry.get("metadata", {})
                );

                # now we attach it to the job
                parameters ++> parameter;
            }
        }
    }

    can on_parameters with Parameters entry {
        for document_entry in self.document{
            if not [-->](`?ParameterEntry)(?condition == document_entry.get("condition")){

                parameter = Parameter(
                    collection_id = here.collection_id,
                    condition = document_entry.get("condition", ""),
                    response = document_entry.get("response", ""),
                    action = document_entry.get("action", ""),
                    enabled = True,
                    metadata = document_entry.get("metadata", {})
                );

                # now we attach it to the parameters node
                here ++> parameter;
            }

        }
    }
}
