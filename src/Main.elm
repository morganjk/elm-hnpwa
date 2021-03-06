module Main exposing (..)

import Dict
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (defaultOptions, onClick, onWithOptions)
import Http exposing (get, send)
import Json.Decode as D exposing (..)
import Json.Decode.Pipeline as P exposing (decode, optional, required)
import Json.Encode as E exposing (..)
import Navigation exposing (Location)
import Route exposing (Route)
import Svg
import Svg.Attributes as SA
import Types exposing (..)


main : Program Never Model Msg
main =
    Navigation.program OnNavigation
        { init = init
        , view = view
        , update = update
        , subscriptions = \_ -> Sub.none
        }


type alias Model =
    { route : Route
    , session : Session
    , page : Page
    }


type Page
    = Feed (List Item)
    | Article Item
    | Profile User
    | Loading
    | Error Http.Error
    | NotFound


type alias Session =
    { feeds : Dict.Dict String (Result Http.Error (List Item))
    , items : Dict.Dict Int (Result Http.Error Item)
    , users : Dict.Dict String (Result Http.Error User)
    }



--INIT


init : Navigation.Location -> ( Model, Cmd Msg )
init location =
    check
        { route = Route.parse location
        , page = Loading
        , session = Session Dict.empty Dict.empty Dict.empty
        }



-- UPDATE


type Msg
    = NewUrl Route
    | OnNavigation Location
    | GotItem Int (Result Http.Error Item)
    | GotUser String (Result Http.Error User)
    | GotFeed String (Result Http.Error (List Item))


update : Msg -> Model -> ( Model, Cmd Msg )
update msg ({ session } as model) =
    case msg of
        NewUrl url ->
            ( model, Navigation.newUrl (Route.toUrl url) )

        OnNavigation location ->
            check { model | route = Route.parse location }

        GotItem id item ->
            check { model | session = { session | items = Dict.insert id item session.items } }

        GotUser id user ->
            check { model | session = { session | users = Dict.insert id user session.users } }

        GotFeed id feed ->
            check { model | session = { session | feeds = Dict.insert id feed session.feeds } }



-- VIEW


view : Model -> Html Msg
view { page, route } =
    let
        viewPage =
            case page of
                Feed items ->
                    viewList route items

                Article item ->
                    viewItem item

                Profile user ->
                    viewUser user

                Loading ->
                    viewLoading

                Error error ->
                    viewError error

                NotFound ->
                    viewNotFound
    in
    main_ []
        [ viewHeader route
        , section [ id "content" ] [ viewPage ]
        ]



-- HEADER VIEW


viewHeader : Route -> Html Msg
viewHeader route =
    header []
        [ link Route.Root [ i [ attribute "aria-label" "Homepage", class "logo" ] [ logo ] ]
        , nav []
            (List.map (headerLink route)
                [ Route.Feeds Route.Top Nothing
                , Route.Feeds Route.New Nothing
                , Route.Feeds Route.Ask Nothing
                , Route.Feeds Route.Show Nothing
                , Route.Feeds Route.Jobs Nothing
                ]
            )
        , a
            [ class "githublink"
            , href "https://github.com/rl-king/elm-hnpwa"
            , target "_blank"
            , rel "noopener"
            ]
            [ text "About" ]
        ]


headerLink : Route -> Route -> Html Msg
headerLink currentRoute route =
    if Route.toTitle currentRoute == Route.toTitle route then
        span [ attribute "aria-current" "page" ] [ text (Route.toTitle route) ]
    else
        link route [ text (Route.toTitle route) ]



-- LIST VIEW


viewList : Route -> List Item -> Html Msg
viewList route feed =
    section [ class "list-view" ]
        [ ul [] (List.indexedMap viewListItem feed)
        , viewPagination route
        ]


viewListItem : Int -> Item -> Html Msg
viewListItem index item =
    li []
        [ aside [] [ text (toString (index + 1)) ]
        , div []
            [ listItemUrl item.id item.url item.title
            , span [ class "domain" ] [ text item.domain ]
            , itemFooter item
            ]
        ]


listItemUrl : Int -> String -> String -> Html Msg
listItemUrl id url title =
    if String.contains "item?id=" url then
        link (Route.Item id) [ text title ]
    else
        a [ href url, target "_blank", rel "noopener" ] [ text title ]


viewPagination : Route -> Html Msg
viewPagination route =
    case Route.toPagination route of
        Just total ->
            section [ class "pagination" ]
                [ previousPageLink route
                , nav [] (List.map (paginationDesktop route) (List.range 1 total))
                , div [ class "mobile" ]
                    [ span [] [ text (toString (Route.toFeedPage route)) ]
                    , span [] [ text "/" ]
                    , span [] [ text (toString total) ]
                    ]
                , nextPageLink route
                ]

        Nothing ->
            text ""


nextPageLink : Route -> Html Msg
nextPageLink route =
    Maybe.map (flip link [ text "Next" ]) (Route.toNext route)
        |> Maybe.withDefault (span [ class "inactive" ] [ text "Next" ])


previousPageLink : Route -> Html Msg
previousPageLink route =
    Maybe.map (flip link [ text "Previous" ]) (Route.toPrevious route)
        |> Maybe.withDefault (span [ class "inactive" ] [ text "Previous" ])


paginationDesktop : Route -> Int -> Html Msg
paginationDesktop route page =
    if page == Route.toFeedPage route then
        span [ attribute "aria-current" "page" ] [ text (toString page) ]
    else
        link (Route.mapFeedPage (\_ -> page) route) [ text (toString page) ]



-- ITEM VIEW


viewItem : Item -> Html Msg
viewItem item =
    article []
        [ section []
            [ itemUrl item.id item.url item.title
            , span [ class "domain" ] [ text item.domain ]
            , itemFooter item
            ]
        , rawHtml div item.content
        , section [ class "comments-view" ]
            [ viewComments (getComments item.comments)
            ]
        ]


itemUrl : Int -> String -> String -> Html Msg
itemUrl id url title =
    if String.contains "item?id=" url then
        h2 [] [ text title ]
    else
        a [ href url, target "_blank", rel "noopener" ] [ h2 [] [ text title ] ]


itemFooter : Item -> Html Msg
itemFooter item =
    if item.type_ == "job" then
        footer [] [ text item.timeAgo ]
    else
        footer []
            [ text (toString item.points ++ " points by ")
            , link (Route.User item.user) [ text item.user ]
            , text (" " ++ item.timeAgo ++ " | ")
            , link (Route.Item item.id) [ text (toString item.commentsCount ++ " comments") ]
            ]



-- COMMENTS VIEW


viewComments : List Item -> Html Msg
viewComments comments =
    ul [] (List.map commentView comments)


commentView : Item -> Html Msg
commentView item =
    li []
        [ div [ class "comment-meta" ]
            [ link (Route.User item.user) [ text item.user ]
            , text (" " ++ item.timeAgo)
            ]
        , rawHtml div item.content
        , viewComments (getComments item.comments)
        ]



-- USER VIEW


viewUser : User -> Html Msg
viewUser user =
    section [ class "user-view" ]
        [ table []
            [ viewRow "user:" user.id
            , viewRow "created:" user.created
            , viewRow "karma:" (toString user.karma)
            , viewRow "about:" user.about
            ]
        ]


viewRow : String -> String -> Html Msg
viewRow x y =
    tr []
        [ td [] [ text x ]
        , td [] [ text y ]
        ]


viewLoading : Html Msg
viewLoading =
    div [ class "notification" ] [ div [ class "spinner" ] [] ]


viewNotFound : Html Msg
viewNotFound =
    div [ class "notification" ] [ text "404" ]


viewError : Http.Error -> Html Msg
viewError error =
    div [ class "notification" ] [ text (httpErrorToString error) ]


httpErrorToString : Http.Error -> String
httpErrorToString error =
    case error of
        Http.Timeout ->
            "Timeout"

        Http.NetworkError ->
            "NetworkError | You seem to be offline"

        Http.BadStatus { status } ->
            "BadStatus | The server gave me a " ++ toString status.code ++ " error"

        Http.BadPayload _ _ ->
            "BadPayload | The server gave me back something I did not expect"

        Http.BadUrl _ ->
            "The Hackernews API seems to have changed"



--VIEW HELPERS


rawHtml : (List (Attribute Msg) -> List (Html Msg) -> Html Msg) -> String -> Html Msg
rawHtml node htmlString =
    node [ property "innerHTML" (E.string htmlString) ] []



-- LINK HELPERS


link : Route -> List (Html Msg) -> Html Msg
link route kids =
    a [ href (Route.toUrl route), onPreventDefaultClick (NewUrl route) ] kids


onPreventDefaultClick : Msg -> Attribute Msg
onPreventDefaultClick msg =
    onWithOptions "click"
        { defaultOptions | preventDefault = True }
        (D.andThen (eventDecoder msg) eventKeyDecoder)


eventKeyDecoder : Decoder Bool
eventKeyDecoder =
    D.map2
        (not >> xor)
        (D.field "ctrlKey" D.bool)
        (D.field "metaKey" D.bool)


eventDecoder : msg -> Bool -> Decoder msg
eventDecoder msg preventDefault =
    if preventDefault then
        D.succeed msg
    else
        D.fail ""



-- COMMENT HELPER


getComments : Comments -> List Item
getComments comments =
    case comments of
        Comments items ->
            items

        Empty ->
            []



-- ROUTE TO REQUEST


check : Model -> ( Model, Cmd Msg )
check ({ route, session } as model) =
    case checkHelper route session of
        Go (Ok page) ->
            ( { model | page = page }, Cmd.none )

        Go (Err err) ->
            ( { model | page = Error err }, Cmd.none )

        Get cmd ->
            ( { model | page = Loading }, cmd )


checkHelper : Route -> Session -> PageHelper (Result Http.Error Page) (Cmd Msg)
checkHelper route session =
    case route of
        Route.Feeds _ _ ->
            Maybe.map (Go << Result.map Feed) (Dict.get (Route.toApi route) session.feeds)
                |> Maybe.withDefault (Get (requestFeed route))

        Route.Item id ->
            Maybe.map (Go << Result.map Article) (Dict.get id session.items)
                |> Maybe.withDefault (Get (requestItem id))

        Route.User id ->
            Maybe.map (Go << Result.map Profile) (Dict.get id session.users)
                |> Maybe.withDefault (Get (requestUser id))

        _ ->
            Go (Ok NotFound)



-- HTTP


endpoint : String
endpoint =
    "https://hnpwa.com/api/v0/"


requestItem : Int -> Cmd Msg
requestItem id =
    Http.get (endpoint ++ "item/" ++ toString id ++ ".json") decodeItem
        |> Http.send (GotItem id)


requestUser : String -> Cmd Msg
requestUser id =
    Http.get (endpoint ++ "user/" ++ id ++ ".json") decodeUser
        |> Http.send (GotUser id)


requestFeed : Route -> Cmd Msg
requestFeed route =
    Http.get (endpoint ++ Route.toApi route) decodeFeed
        |> Http.send (GotFeed (Route.toApi route))



--DECODERS


decodeFeed : D.Decoder (List Item)
decodeFeed =
    D.list decodeItem


decodeItem : D.Decoder Item
decodeItem =
    P.decode Item
        |> P.required "id" D.int
        |> P.optional "title" D.string "No title"
        |> P.optional "points" D.int 0
        |> P.optional "user" D.string ""
        |> P.required "time_ago" D.string
        |> P.optional "url" D.string ""
        |> P.optional "domain" D.string ""
        |> P.required "comments_count" D.int
        |> P.optional "comments" (D.lazy (\_ -> decodeComments)) Empty
        |> P.optional "content" D.string ""
        |> P.required "type" D.string


decodeUser : D.Decoder User
decodeUser =
    P.decode User
        |> P.optional "title" D.string ""
        |> P.required "created" D.string
        |> P.required "id" D.string
        |> P.required "karma" D.int


decodeComments : Decoder Comments
decodeComments =
    D.map Comments (D.list (D.lazy (\_ -> decodeItem)))



-- LOGO


logo : Svg.Svg Msg
logo =
    Svg.svg [ width 25, height 26, SA.viewBox "0 0 25 26" ]
        [ Svg.g [ SA.fill "none" ]
            [ Svg.path [ SA.fill "#FFFFFF", SA.d "M12.4 6l5.3.2L12.3.8m0 12.5v5.3l5.4-5.3" ] []
            , Svg.path [ SA.fill "#FFFFFF", SA.d "M12.3 25v-5.3l6-6v5.5m-6-12.4h6v5.8h-6z" ] []
            , Svg.path [ SA.fill "#FFFFFF", SA.d "M19 18.4l5.3-5.4L19 7.5" ] []
            , Svg.path [ SA.fill "#FFFFFF", SA.d "M11.7.8H0l11.7 11.7" ] []
            , Svg.path [ SA.fill "#FFFFFF", SA.d "M11.7 25.2V13.5L0 25.2" ] []
            ]
        ]
