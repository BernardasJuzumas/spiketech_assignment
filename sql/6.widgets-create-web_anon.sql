create role web_anon nologin;

create role authenticator noinherit login password 'mysecretpassword';
grant web_anon to authenticator;

grant usage on schema widgets to web_anon;

grant execute on function widgets.add_widget(text, text, text[]) to web_anon;
grant execute on function widgets.associate_widgets(text, text, widgets.port_type) to web_anon;
grant execute on function widgets.remove_association(text, text, widgets.port_type) to web_anon;
grant execute on function widgets.remove_widget(text) to web_anon;

